import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/safe_subprocess.dart';

void main() {
  late Directory tempDirectory;
  late File helperScript;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'openhand-safe-subprocess-',
    );
    helperScript = File('${tempDirectory.path}/helper.dart');
    await helperScript.writeAsString('''
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.firstOrNull == 'wait') {
    await Future<void>.delayed(const Duration(seconds: 30));
    return;
  }
  stdout.writeln(' first ');
  stdout.writeln('second-output');
  stdout.writeln('third');
  stderr.writeln(' warning ');
}
''');
  });

  tearDownAll(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('line logging streams and captures bounded normalized output', () async {
    final stdoutLines = <String>[];
    final stderrLines = <String>[];

    final result = await runTrackedProcessWithLineLogging(
      'dart',
      <String>[helperScript.path, 'output'],
      timeout: const Duration(seconds: 5),
      startInNewProcessGroup: false,
      trimStdoutLines: true,
      maxCapturedLinesPerStream: 2,
      maxLineCharacters: 6,
      onStdoutLine: stdoutLines.add,
      onStderrLine: stderrLines.add,
    );

    expect(result.exitCode, 0);
    expect(result.timedOut, isFalse);
    expect(stdoutLines, <String>['first', 'second…', 'third']);
    expect(stderrLines, <String>['warnin…']);
    expect(result.stdout, 'second…\nthird');
    expect(result.stderr, 'warnin…');
  });

  test('line logging bounds timeout and terminates the process', () async {
    final stopwatch = Stopwatch()..start();

    final result = await runTrackedProcessWithLineLogging(
      'dart',
      <String>[helperScript.path, 'wait'],
      timeout: const Duration(milliseconds: 100),
      gracefulTerminationTimeout: const Duration(milliseconds: 50),
      startInNewProcessGroup: false,
    );

    stopwatch.stop();
    expect(result.exitCode, -1);
    expect(result.timedOut, isTrue);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
  });
}
