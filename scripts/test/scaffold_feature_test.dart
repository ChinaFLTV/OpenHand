import 'dart:io';
import 'package:test/test.dart';

void main() {
  final scriptPath = File('scripts/scaffold_feature.dart').absolute.path;

  Future<ProcessResult> runScaffold(
    List<String> args, {
    required String workingDirectory,
  }) {
    return Process.run('dart', [
      'run',
      scriptPath,
      ...args,
    ], workingDirectory: workingDirectory);
  }

  test('scaffold_feature happy path generates expected files', () async {
    final tmp = await Directory.systemTemp.createTemp('scaffold_feature_test_');
    final result = await runScaffold(['foo_bar'], workingDirectory: tmp.path);
    expect(
      result.exitCode,
      0,
      reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
    );

    final featureDir = '${tmp.path}/lib/features/foo_bar';

    final controller = File(
      '$featureDir/foo_bar_controller.dart',
    ).readAsStringSync();
    expect(
      controller,
      contains('class FooBarController extends ChangeNotifier'),
    );

    final module = File('$featureDir/foo_bar_module.dart').readAsStringSync();
    expect(module, contains('class FooBarModule'));
    expect(module, contains('static Future<FooBarController> bootstrap()'));
    expect(
      module,
      contains(
        'static List<SingleChildWidget> providers(FooBarController controller)',
      ),
    );

    final index = File('$featureDir/index.dart').readAsStringSync();
    expect(index, contains("export 'foo_bar_controller.dart';"));
    expect(index, contains("export 'foo_bar_module.dart';"));

    expect(File('$featureDir/README.md').existsSync(), isTrue);

    for (final sub in const ['model', 'data', 'service', 'widgets', 'state']) {
      expect(
        File('$featureDir/$sub/.gitkeep').existsSync(),
        isTrue,
        reason: 'expected $sub/.gitkeep',
      );
    }
  });

  test('scaffold_feature no-arg path exits 2 with usage', () async {
    final tmp = await Directory.systemTemp.createTemp('scaffold_feature_test_');
    final result = await runScaffold([], workingDirectory: tmp.path);
    expect(result.exitCode, 2);
    expect(result.stderr.toString(), contains('usage'));
  });

  test(
    'scaffold_feature bad-name path exits 2 with snake_case message',
    () async {
      final tmp = await Directory.systemTemp.createTemp(
        'scaffold_feature_test_',
      );
      final result = await runScaffold(['BadName'], workingDirectory: tmp.path);
      expect(result.exitCode, 2);
      expect(result.stderr.toString(), contains('snake_case'));
    },
  );

  test('scaffold_feature already-exists path exits 1 on second run', () async {
    final tmp = await Directory.systemTemp.createTemp('scaffold_feature_test_');
    final first = await runScaffold(['foo_bar'], workingDirectory: tmp.path);
    expect(first.exitCode, 0, reason: 'first run failed: ${first.stderr}');

    final second = await runScaffold(['foo_bar'], workingDirectory: tmp.path);
    expect(second.exitCode, 1);
    expect(second.stderr.toString(), contains('already exists'));
  });
}
