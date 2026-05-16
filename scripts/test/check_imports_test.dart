import 'dart:io';
import 'package:test/test.dart';

void main() {
  final scriptPath = Platform.script
      .resolve('../check_imports.dart')
      .toFilePath();

  test('check_imports rejects cross-feature deep import', () async {
    final tmp = await Directory.systemTemp.createTemp('check_imports_test');
    final f = File('${tmp.path}/lib/features/a/widgets/x.dart')
      ..createSync(recursive: true);
    f.writeAsStringSync(
      "import '../../b/service/y.dart';\n",
    );
    final result = await Process.run('dart', [
      'run',
      scriptPath,
      tmp.path,
    ]);
    expect(result.exitCode, isNonZero);
    expect(result.stderr.toString(), contains('deep cross-feature import'));
  });

  test('check_imports accepts barrel import', () async {
    final tmp = await Directory.systemTemp.createTemp('check_imports_test');
    final f = File('${tmp.path}/lib/features/a/widgets/x.dart')
      ..createSync(recursive: true);
    f.writeAsStringSync("import '../../b/index.dart';\n");
    File('${tmp.path}/lib/features/b/index.dart').createSync(recursive: true);
    final result = await Process.run('dart', [
      'run',
      scriptPath,
      tmp.path,
    ]);
    expect(result.exitCode, 0);
  });

  test('check_imports rejects widgets → service same-feature import', () async {
    final tmp = await Directory.systemTemp.createTemp('check_imports_test');
    final f = File('${tmp.path}/lib/features/a/widgets/x.dart')
      ..createSync(recursive: true);
    f.writeAsStringSync("import '../service/y.dart';\n");
    final result = await Process.run('dart', [
      'run',
      scriptPath,
      tmp.path,
    ]);
    expect(result.exitCode, isNonZero);
    expect(result.stderr.toString(), contains('widgets → service forbidden'));
  });

  test('check_imports rejects TS deep cross-feature import', () async {
    final tmp = await Directory.systemTemp.createTemp('check_imports_test');
    final f = File('${tmp.path}/clients/web/src/features/a/components/x.tsx')
      ..createSync(recursive: true);
    f.writeAsStringSync("import { y } from '@/features/b/api/y';\n");
    final result = await Process.run('dart', [
      'run',
      scriptPath,
      tmp.path,
    ]);
    expect(result.exitCode, isNonZero);
    expect(result.stderr.toString(), contains('deep cross-feature import'));
  });

  test('check_imports accepts TS barrel import', () async {
    final tmp = await Directory.systemTemp.createTemp('check_imports_test');
    final f = File('${tmp.path}/clients/web/src/features/a/components/x.tsx')
      ..createSync(recursive: true);
    f.writeAsStringSync("import { y } from '@/features/b';\n");
    final result = await Process.run('dart', [
      'run',
      scriptPath,
      tmp.path,
    ]);
    expect(result.exitCode, 0);
  });
}
