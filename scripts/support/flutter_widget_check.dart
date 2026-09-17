import 'dart:io';

/// 在临时目录执行真实 Flutter 组件检查，退出后清理生成文件。
Future<void> runFlutterWidgetCheck({
  required Directory root,
  required String name,
  required String source,
}) async {
  final directory = await Directory(
    '${root.path}/.dart_tool',
  ).createTemp('${name}_check_');
  try {
    final file = File('${directory.path}/${name}_test.dart');
    await file.writeAsString(source);
    final process = await Process.start(
      'flutter',
      ['test', '--reporter', 'expanded', file.path],
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await process.exitCode;
  } finally {
    await directory.delete(recursive: true);
  }
}
