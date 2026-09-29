import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final source = await File(
    '${root.path}/lib/features/machine_terminal/machine_terminal_file_service.dart',
  ).readAsString();
  final commands = source.substring(
    source.indexOf('String _parallelWindowsFileCommands'),
    source.indexOf('String _fileDetailsCommand'),
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'machine_file_workers',
    source:
        '''
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_parallel.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_file_service.dart';
import 'package:openhand/shared/util/platform_shell.dart';
const _machineTerminalDirectoryEntryLimit = 2000;
const _machineTerminalFileWorkers = 8;
$commands
$_checks
''',
  );
}

const _checks = r'''
void main() {
  test('八路目录读取保留特殊名称、链接与子项数量，失败不伪装为空目录', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('openhand-file-workers-');
    try {
      final names = [for (var i = 0; i < 33; i++) '文件 $i', '.隐藏', '单引号\'与换行\n'];
      for (final name in names) { await File('${root.path}/$name').writeAsString('内容'); }
      final child = await Directory('${root.path}/子目录').create();
      await File('${child.path}/文件').writeAsString('内容');
      await Directory('${child.path}/下级').create();
      await Link('${root.path}/链接').create('${root.path}/${names.first}');
      final command = _listDirectoryCommand(root.path);
      expect(command, contains('oh_workers=8'));
      final result = await Process.run('sh', ['-c', command]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final output = result.stdout as String;
      final rows = const LineSplitter().convert(output).where((line) => line.startsWith('E\t')).map((line) => line.split('\t')).toList();
      final actual = rows.map((row) => utf8.decode(base64Decode(row[5]))).toList();
      expect(actual.toSet(), {...names, '子目录', '链接'});
      expect(actual.length, actual.toSet().length);
      final directory = rows.singleWhere((row) => utf8.decode(base64Decode(row[5])) == '子目录');
      expect(directory.sublist(7), ['1', '1']);
      final missing = await Process.run('sh', ['-c', _listDirectoryCommand('${root.path}/不存在')]);
      expect(missing.exitCode, isNot(0));
    } finally { await root.delete(recursive: true); }
  });
}
''';
