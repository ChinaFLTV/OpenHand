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
  final large = MachineLogBuffer();
  large.append(List.generate(200, (i) => '$i ${'x' * 7000}').join('\n'));
  check(
    large.entries.fold<int>(
          0,
          (sum, entry) => sum + entry.time.length + entry.message.length + 3,
        ) <=
        machineLogTextLimit,
    '长日志文本缓存超过上限',
  );
  check(large.entries.last.message.startsWith('199 '), '长日志缓存必须保留最新记录');
  final cleared = MachineLogBuffer()..append('a\nb\nb');
  cleared.clear();
  cleared.append('a\nb\nb');
  check(cleared.entries.isEmpty, '清屏后相同采样重新显示旧记录');
  cleared.append('b\nb\nc');
  check(cleared.entries.single.message == 'c', '清屏后没有正确接收新增记录');
  journal.clear();
  final restored = MachineLogBuffer.copy(journal);
  restored.append(record(2));
  check(restored.entries.isEmpty && restored.error == null, '复制缓存丢失清屏去重状态');
  restored.append(record(3));
  check(restored.entries.single.id == '3', '清屏后遗漏新的原生事件');
  final container = MachineLogBuffer();
  final lines = [
    '{"MESSAGE":"应用原始日志"}',
    '<Events>应用原始日志</Events>',
    'dmesg: 应用原始日志',
    ...List.generate(297, (index) => '记录 $index'),
  ];
  container.append(lines.join('\n'), plainText: true);
  check(
    container.entries.length == 300 &&
        container.entries.first.message == lines.first,
    '容器原始日志被误解析或截断',
  );
  container.clear();
  container.append([...lines.skip(1), '新增记录'].join('\n'), plainText: true);
  check(container.entries.single.message == '新增记录', '容器日志滚动采样重新显示已清除内容');
  container.clear();
  container.append('', plainText: true);
  container.append('新增记录', plainText: true);
  check(container.entries.isEmpty, '空采样破坏清屏后的去重状态');
  stdout.writeln('日志解析、清屏续收、追加去重、异常保留及缓存边界检查通过。');
}
