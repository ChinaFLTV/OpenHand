import 'dart:convert';
import 'dart:io';
import 'package:openhand/features/machine_terminal/machine_maintenance_logs.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final buffer = MachineLogBuffer();
  buffer.append('a\nb\nb');
  buffer.append('b\nb\nc');
  check(
    buffer.entries.map((e) => e.message).join(',') == 'a,b,b,c',
    '重叠合并丢失重复记录',
  );
  buffer.append('dmesg: read kernel buffer failed: Operation not permitted');
  check(buffer.error != null && buffer.entries.length == 4, '权限错误破坏已有记录');
  buffer.append('Sep 29 kernel: failed to allocate');
  check(buffer.error == null && buffer.entries.last.level == 0, '真实错误日志被误判');
  final journal = MachineLogBuffer();
  String record(int id) => jsonEncode({
    '__CURSOR': '$id',
    '__REALTIME_TIMESTAMP': '1790000000000000',
    'MESSAGE': '同一时刻消息',
    'PRIORITY': '4',
  });
  journal.append(record(1));
  journal.append(record(2));
  journal.append(record(1));
  check(
    journal.entries.length == 2 && journal.entries.first.level == 1,
    '日志原生标识去重失败',
  );
  journal.append('{broken');
  check(journal.entries.length == 2 && journal.error != null, '损坏响应覆盖旧日志');
  final windows = MachineLogBuffer();
  windows.append(
    '<Events><Event><System><Channel>System</Channel><EventRecordID>42</EventRecordID><Level>2</Level><TimeCreated SystemTime="2026-09-29T10:00:00Z"/></System><EventData><Data Name="Code">123</Data></EventData></Event></Events>',
  );
  check(
    windows.entries.single.id == 'System:42' &&
        windows.entries.single.message == 'Code: 123',
    'Windows 事件解析错误',
  );
  for (var batch = 0; batch < 10; batch++) {
    buffer.append(
      List.generate(200, (i) => '记录 ${batch * 200 + i}').join('\n'),
    );
  }
  check(
    buffer.entries.length == machineLogLimit &&
        buffer.entries.last.message == '记录 1999',
    '缓存上限失效',
  );
  stdout.writeln('日志解析、追加合并、重复记录、异常保留及缓存边界检查通过。');
}
