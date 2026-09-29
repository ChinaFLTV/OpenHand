import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_parallel.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_platform.dart';
import 'package:openhand/shared/util/platform_shell.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> waitFor(bool Function() ready, String message) async {
  for (var i = 0; i < 100; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(message);
}

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('openhand-并行检查-');
  final environment = {'TMPDIR': directory.path};
  try {
    final events = File('${directory.path}/events');
    final source =
        '''
section() { printf '\\n__OH_OPS_%s__\\n' "\$1"; }
section platform
printf 'Linux\\n'
${[
          for (final name in ['alpha', 'beta', 'gamma', 'delta']) '''section $name
printf '开始 $name\\n' >> ${posixShellQuote(events.path)}
sleep .3
printf '$name 内容\\n'
printf '完成 $name\\n' >> ${posixShellQuote(events.path)}
''',
        ].join()}
section end
''';
    final times = <int>[];
    for (final workers in [1, 2, 4]) {
      await events.writeAsString('');
      final timer = Stopwatch()..start();
      final result = await Process.run('sh', [
        '-c',
        parallelMaintenanceCommand(source, workers, 0),
      ], environment: environment);
      check(result.exitCode == 0, '并行采集执行失败：${result.stderr}');
      final sample = MachineMaintenanceSnapshot.parse(result.stdout as String);
      check(
        sample.text('alpha') == 'alpha 内容' &&
            sample.text('delta') == 'delta 内容',
        '采集输出串线',
      );
      var active = 0, peak = 0;
      for (final line in await events.readAsLines()) {
        active += line.startsWith('开始') ? 1 : -1;
        if (active > peak) peak = active;
      }
      check(active == 0 && peak == workers, '采集并发上限不正确：$peak / $workers');
      check(directory.listSync().whereType<Directory>().isEmpty, '正常采集遗留私有目录');
      times.add(timer.elapsedMilliseconds);
    }
    check(times.last < times.first * .8, '并行采集未带来预期提速');
    stdout.writeln('1 / 2 / 4 个采集任务耗时：${times.join(' / ')} 毫秒；并发上限、输出隔离与清理通过。');

    for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigkill]) {
      final witness = File('${directory.path}/child');
      if (witness.existsSync()) witness.deleteSync();
      final command =
          '''
section() { printf '\\n__OH_OPS_%s__\\n' "\$1"; }
section platform
printf 'Linux\\n'
section slow
sh -c 'trap "" TERM HUP; echo \$\$ > ${posixShellQuote(witness.path)}; while :; do sleep 1; done' &
wait
section end
''';
      final parent = await Process.start('sh', [
        '-c',
        '${parallelMaintenanceCommand(command, 1, 0)} & wait',
      ], environment: environment);
      final output = parent.stdout.drain<void>();
      final errors = parent.stderr.drain<void>();
      await waitFor(
        () =>
            witness.existsSync() &&
            witness.readAsStringSync().trim().isNotEmpty,
        '采集孙进程未启动',
      );
      final child = int.parse(witness.readAsStringSync().trim());
      parent.kill(signal);
      await parent.exitCode.timeout(const Duration(seconds: 5));
      await Future.wait([output, errors]).timeout(const Duration(seconds: 5));
      await waitFor(
        () => directory.listSync().whereType<Directory>().isEmpty,
        '关闭父终端后遗留采集目录',
      );
      final state = await Process.run('ps', ['-o', 'stat=', '-p', '$child']);
      check(
        (state.stdout as String).trim().isEmpty ||
            (state.stdout as String).trim().startsWith('Z'),
        '关闭父终端后孙进程仍在运行：$child',
      );
    }
    stdout.writeln('父终端正常终止、强杀及忽略 TERM 的孙进程回收通过。');

    final timeout = Stopwatch()..start();
    final timedOut = await Process.run('sh', [
      '-c',
      parallelMaintenanceCommand(
        "section() { printf '\\n__OH_OPS_%s__\\n' \"\$1\"; }\nsection platform\nprintf 'Linux\\n'\nsection slow\nsleep 30\nsection end\n",
        1,
        0,
      ),
    ], environment: environment).timeout(const Duration(seconds: 28));
    check(
      timedOut.exitCode != 0 && timeout.elapsed.inSeconds < 27,
      '采集超时未被有界终止',
    );
    check(directory.listSync().whereType<Directory>().isEmpty, '超时后遗留采集目录');
    stdout.writeln('采集超时终止与目录回收通过。');

    if (Platform.isMacOS || Platform.isLinux) {
      final adapter = MachineMaintenancePlatformAdapter.forPlatform(
        Platform.isMacOS ? 'Darwin' : 'Linux',
      );
      for (var tab = 0; tab < 4; tab++) {
        final result = await Process.run('sh', [
          '-c',
          adapter.collect(tab, workers: 4),
        ], environment: environment).timeout(const Duration(seconds: 30));
        check(
          result.exitCode == 0,
          '实机采集分区 $tab 失败：${result.stderr} ${result.stdout}',
        );
        final sample = MachineMaintenanceSnapshot.parse(
          result.stdout as String,
        );
        check(sample.sections.length > 3, '实机采集结果不完整');
        stdout.writeln('实机分区 $tab 并行采集通过，${sample.sections.length} 个数据段。');
      }
    }
    for (final platform in ['Linux', 'Darwin']) {
      for (var tab = 0; tab < 4; tab++) {
        final process = await Process.start('sh', ['-n']);
        process.stdin.write(
          MachineMaintenancePlatformAdapter.forPlatform(
            platform,
          ).collect(tab, workers: 8),
        );
        await process.stdin.close();
        check(await process.exitCode == 0, '$platform 采集脚本语法错误');
      }
    }
  } finally {
    await directory.delete(recursive: true);
  }
}
