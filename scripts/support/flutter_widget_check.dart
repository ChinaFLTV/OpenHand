import 'dart:io';

/// 将真实实现嵌入临时检查库，统一解析依赖，避免为私有状态新增生产接口。
Future<String> readFlutterCheckSource(
  File file, {
  required Directory root,
  bool inlineParts = false,
}) async {
  final libUri = Directory('${root.path}/lib/').uri.toString();
  final source = (await file.readAsString()).replaceAllMapped(
    RegExp("(import|export) '([^']+)'"),
    (match) {
      final uri = file.uri.resolve(match[2]!);
      final resolved = uri.toString();
      final target = resolved.startsWith(libUri)
          ? 'package:openhand/${resolved.substring(libUri.length)}'
          : resolved;
      return "${match[1]} '$target'";
    },
  );
  if (!inlineParts) return source;

  final combined = StringBuffer();
  var offset = 0;
  for (final match in RegExp("part '([^']+)';").allMatches(source)) {
    combined.write(source.substring(offset, match.start));
    final part = await File.fromUri(file.uri.resolve(match[1]!)).readAsString();
    combined.write(
      part.replaceFirst(RegExp('^part of [^;]+;', multiLine: true), ''),
    );
    offset = match.end;
  }
  combined.write(source.substring(offset));
  return combined.toString();
}

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
