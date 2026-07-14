import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_lsp_language_settings.dart';
import 'package:openhand/features/ai/service/lsp/lsp_client_service.dart';
import 'package:path/path.dart' as p;

Future<Process> _unusedProcessLauncher({
  required AiLspBackendResolution backend,
  Map<String, String>? environment,
}) async {
  throw StateError('The resolution tests must not launch an LSP process.');
}

void main() {
  late Directory temporaryDirectory;
  late AiLspClientService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-lsp-resolution-',
    );
    await File(
      p.join(temporaryDirectory.path, 'pubspec.yaml'),
    ).writeAsString('name: resolution_test');
    service = AiLspClientService.forTesting(
      processLauncher: _unusedProcessLauncher,
    );
  });

  tearDown(() async {
    await service.disposeAll();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('configured executable file resolves asynchronously', () async {
    final executable = File(p.join(temporaryDirectory.path, 'custom-dart'));
    await executable.writeAsString('binary');
    service.updateLanguageSettings(<String, AiLspLanguageSettings>{
      'dart': AiLspLanguageSettings(rootPath: executable.path),
    });

    final resolution = await service.resolveBackendForFile(
      filePath: p.join(temporaryDirectory.path, 'lib', 'main.dart'),
      language: 'dart',
    );

    expect(resolution.isAvailable, isTrue);
    expect(resolution.executablePath, executable.path);
    expect(resolution.rootPath, temporaryDirectory.path);
  });

  test('configured directory resolves an executable in bin', () async {
    final sdkRoot = Directory(p.join(temporaryDirectory.path, 'sdk'));
    final executable = File(p.join(sdkRoot.path, 'bin', 'dart'));
    await executable.parent.create(recursive: true);
    await executable.writeAsString('binary');
    service.updateLanguageSettings(<String, AiLspLanguageSettings>{
      'dart': AiLspLanguageSettings(rootPath: sdkRoot.path),
    });

    final resolution = await service.resolveBackendForFile(
      filePath: p.join(temporaryDirectory.path, 'lib', 'main.dart'),
      language: 'dart',
    );

    expect(resolution.isAvailable, isTrue);
    expect(resolution.executablePath, executable.path);
  });

  test('configured directory rejects a same-name subdirectory', () async {
    final sdkRoot = Directory(p.join(temporaryDirectory.path, 'sdk'));
    await Directory(
      p.join(sdkRoot.path, 'bin', 'dart'),
    ).create(recursive: true);
    service.updateLanguageSettings(<String, AiLspLanguageSettings>{
      'dart': AiLspLanguageSettings(rootPath: sdkRoot.path),
    });

    final resolution = await service.resolveBackendForFile(
      filePath: p.join(temporaryDirectory.path, 'lib', 'main.dart'),
      language: 'dart',
    );

    expect(
      resolution.availability,
      AiLspBackendAvailability.executableNotFound,
    );
    expect(resolution.executablePath, isNull);
  });
}
