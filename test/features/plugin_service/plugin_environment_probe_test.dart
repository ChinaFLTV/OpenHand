import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/plugin_service/service/plugin_environment_probe.dart';
import 'package:path/path.dart' as p;

import '../../support/test_directory.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-plugin-environment-',
    );
  });

  tearDown(() => deleteTestDirectory(temporaryDirectory));

  test('detects a pyenv executable under the selected home', () async {
    final executable = File(
      p.join(temporaryDirectory.path, '.pyenv', 'bin', 'pyenv'),
    );
    await executable.parent.create(recursive: true);
    await executable.writeAsString('binary');

    expect(
      await pluginPyenvInstallationExists(
        homeDirectory: temporaryDirectory.path,
      ),
      isTrue,
    );
  });

  test('detects Docker Desktop only for macOS probes', () async {
    final applications = Directory(
      p.join(temporaryDirectory.path, 'Applications'),
    );
    await Directory(
      p.join(applications.path, 'Docker.app'),
    ).create(recursive: true);

    expect(
      await pluginDockerDesktopInstallationExists(
        isMacOS: true,
        systemApplicationsDirectory: applications.path,
        homeDirectory: '',
      ),
      isTrue,
    );
    expect(
      await pluginDockerDesktopInstallationExists(
        isMacOS: false,
        systemApplicationsDirectory: applications.path,
      ),
      isFalse,
    );
  });
}
