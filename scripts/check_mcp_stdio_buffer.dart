import 'dart:io';

import 'support/flutter_widget_check.dart';

/// 在隔离管理器中验证突发日志裁剪，不启动真实服务或访问用户数据。
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final file = File(
    '${root.path}/lib/features/mcp/service/mcp_stdio_process_manager.dart',
  );
  final source = await readFlutterCheckSource(file, root: root);
  await runFlutterWidgetCheck(
    root: root,
    name: 'mcp_stdio_buffer',
    source:
        "import 'package:flutter_test/flutter_test.dart';\n$source\n$_checks",
  );
}

const _checks = r'''
void main() {
  test('突发日志仅保留最新两千行且顺序正确', () {
    final manager = McpStdioProcessManager._();
    manager._processes['测试服务'] = const _ManagedProcess(
      generation: 1, configFingerprint: '测试配置', info: StdioProcessInfo(),
    );
    var notifications = 0;
    manager.addListener(() => notifications++);
    final batch = List.generate(100000, (index) => '日志_$index').join('\n');
    final clock = Stopwatch()..start();
    manager._appendLog('测试服务', batch, isStderr: true, expectedGeneration: 1);
    clock.stop();
    final logs = manager.infoFor('测试服务').logs;
    expect(logs.length, McpStdioProcessManager._maxLogLines);
    expect(logs.first, '[标准错误] 日志_98000');
    expect(logs.last, '[标准错误] 日志_99999');
    expect(notifications, 1);
    // 记录耗时供人工对比，不用设备相关的绝对耗时作为通过条件。
    print('十万行突发日志处理耗时：${clock.elapsedMilliseconds} 毫秒');
    manager._appendLog('测试服务', '过期日志', isStderr: true, expectedGeneration: 0);
    expect(identical(manager.infoFor('测试服务').logs, logs), isTrue);
    manager._processes.clear();
    manager.dispose();
  });
}
''';
