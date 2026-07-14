import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/workspace_root_resolver.dart';
import 'package:path/path.dart' as p;

import '../../support/test_directory.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-workspace-root-',
    );
  });

  tearDown(() => deleteTestDirectory(temporaryDirectory));

  test('resolves and caches the nearest workspace marker', () async {
    final root = Directory(p.join(temporaryDirectory.path, 'project'));
    final nested = Directory(p.join(root.path, 'lib', 'src'));
    await nested.create(recursive: true);
    await File(p.join(root.path, 'pubspec.yaml')).writeAsString('name: app');
    final filePath = p.join(nested.path, 'main.dart');
    final resolver = WorkspaceRootResolver(
      markers: const <String>['pubspec.yaml'],
    );

    expect(await resolver.resolve(filePath), root.path);
    expect(resolver.cachedOrFallback(filePath), root.path);
  });

  test(
    'a project result never poisons its parent or sibling project',
    () async {
      final firstRoot = Directory(p.join(temporaryDirectory.path, 'first'));
      final secondRoot = Directory(p.join(temporaryDirectory.path, 'second'));
      await Directory(p.join(firstRoot.path, 'lib')).create(recursive: true);
      await Directory(p.join(secondRoot.path, 'lib')).create(recursive: true);
      await File(p.join(firstRoot.path, 'marker')).writeAsString('first');
      await File(p.join(secondRoot.path, 'marker')).writeAsString('second');
      final resolver = WorkspaceRootResolver(markers: const <String>['marker']);

      expect(
        await resolver.resolve(p.join(firstRoot.path, 'lib', 'a.txt')),
        firstRoot.path,
      );
      expect(
        await resolver.resolve(p.join(secondRoot.path, 'lib', 'b.txt')),
        secondRoot.path,
      );
    },
  );

  test('rejects unsafe markers and invalid limits', () {
    expect(
      () => WorkspaceRootResolver(markers: const <String>['../marker']),
      throwsArgumentError,
    );
    expect(
      () => WorkspaceRootResolver(
        markers: const <String>['marker'],
        maxPendingProbes: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => WorkspaceRootResolver(
        markers: const <String>['marker'],
        totalTimeout: const Duration(minutes: 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => WorkspaceRootResolver(
        markers: const <String>['a', 'b'],
        maxMarkers: 1,
      ),
      throwsArgumentError,
    );
  });
}
