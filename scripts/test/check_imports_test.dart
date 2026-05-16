import 'dart:io';
import 'package:test/test.dart';

void main() {
  test('check_imports rejects cross-feature deep import', () async {
    final tmp = await Directory.systemTemp.createTemp('check_imports_test');
    final f = File('${tmp.path}/lib/features/a/widgets/x.dart')
      ..createSync(recursive: true);
    f.writeAsStringSync(
      "import '../../b/service/y.dart';\n",
    );
    final result = await Process.run('dart', [
      'run',
      'scripts/check_imports.dart',
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
      'scripts/check_imports.dart',
      tmp.path,
    ]);
    expect(result.exitCode, 0);
  });
}
