import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/android_reverse/android_reverse_adb_client.dart';

void main() {
  group('normalizeAdbConnectResult', () {
    test('将退出码为零的连接失败修正为失败', () {
      const raw = AdbCommandResult(
        args: <String>['connect', '127.0.0.1:1'],
        exitCode: 0,
        stdout: "failed to connect to '127.0.0.1:1': Connection refused",
        stderr: '',
      );

      final result = normalizeAdbConnectResult(raw);

      expect(result.ok, isFalse);
      expect(result.exitCode, -1);
      expect(result.stderr, contains('failed to connect'));
    });

    test('保留正常连接和已连接结果', () {
      const connected = AdbCommandResult(
        args: <String>['connect', '127.0.0.1:5555'],
        exitCode: 0,
        stdout: 'connected to 127.0.0.1:5555',
        stderr: '',
      );
      const existing = AdbCommandResult(
        args: <String>['connect', '127.0.0.1:5555'],
        exitCode: 0,
        stdout: 'already connected to 127.0.0.1:5555',
        stderr: '',
      );

      expect(normalizeAdbConnectResult(connected), same(connected));
      expect(normalizeAdbConnectResult(existing), same(existing));
    });
  });

  group('parseAndroidProcessList', () {
    test('解析标准 Android ps 输出', () {
      const raw = '''
USER      PID   PPID  VSZ      RSS   WCHAN            ADDR S NAME
u0_a123   3210  812   1234567  45678 futex_wait_queue 0    S com.example.app
root      77    2     0        0     worker_thread    0    S kworker/0:1
''';

      final result = parseAndroidProcessList(raw);

      expect(result, hasLength(2));
      expect(result.first.pid, 3210);
      expect(result.first.ppid, 812);
      expect(result.first.user, 'u0_a123');
      expect(result.first.name, 'com.example.app');
    });

    test('兼容精简列和命令行列', () {
      const raw = '''
USER PID PPID CMDLINE
u0_a7 201 1 com.example.worker --service sync
root 9 2 [kworker/0:0]
''';

      final result = parseAndroidProcessList(raw);

      expect(result, hasLength(2));
      expect(result.first.name, 'com.example.worker');
      expect(result.last.name, '[kworker/0:0]');
    });

    test('无表头时使用常见列布局并忽略坏行', () {
      const raw = '''
u0_a1 101 1 1000 200 0 0 S com.example.one
bad-line
u0_a2 not-a-pid 1 1000 200 0 0 S com.example.bad
''';

      final result = parseAndroidProcessList(raw);

      expect(result, hasLength(1));
      expect(result.single.name, 'com.example.one');
    });

    test('进程名过滤不区分大小写', () {
      const raw = '''
USER PID PPID NAME
u0_a1 101 1 com.example.Main
u0_a2 102 1 com.other.worker
''';

      final result = parseAndroidProcessList(raw, filterName: 'EXAMPLE');

      expect(result, hasLength(1));
      expect(result.single.pid, 101);
    });
  });
}
