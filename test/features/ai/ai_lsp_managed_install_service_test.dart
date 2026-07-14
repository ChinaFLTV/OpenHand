import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_lsp_backend_catalog.dart';
import 'package:openhand/features/ai/model/ai_lsp_language_settings.dart';
import 'package:openhand/features/ai/service/lsp/ai_lsp_managed_install_service.dart';

const _backend = AiLspBackendDescriptor(
  id: 'test-backend',
  displayName: 'Test Backend',
  languages: <String>{'dart'},
  executable: 'test-lsp',
  install: AiLspManagedInstallRecipe.npmLocal(
    versionedPackages: <String>['test-lsp'],
  ),
);

const _otherBackend = AiLspBackendDescriptor(
  id: 'other-backend',
  displayName: 'Other Backend',
  languages: <String>{'dart'},
  executable: 'other-lsp',
  install: AiLspManagedInstallRecipe.npmLocal(
    versionedPackages: <String>['other-lsp'],
  ),
);

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-managed-lsp-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  AiLspLanguageSettings settingsFor(String rootPath) =>
      AiLspLanguageSettings(backendId: _backend.id, rootPath: rootPath);

  Future<String?> validate(String rootPath) {
    return AiLspManagedInstallService.validateInstallRoot(
      language: 'dart',
      backend: _backend,
      settings: settingsFor(rootPath),
    );
  }

  test('accepts an empty install directory', () async {
    expect(await validate(temporaryDirectory.path), isNull);
  });

  test('rejects a non-empty unmanaged install directory', () async {
    await File('${temporaryDirectory.path}/existing.txt').writeAsString('x');

    expect(await validate(temporaryDirectory.path), contains('not empty'));
  });

  test('accepts existing content managed by the same backend', () async {
    await AiLspManagedInstallService.writeManifest(
      rootPath: temporaryDirectory.path,
      language: 'dart',
      backend: _backend,
      version: '1.0.0',
    );
    await File('${temporaryDirectory.path}/installed.txt').writeAsString('x');

    expect(await validate(temporaryDirectory.path), isNull);
  });

  test('rejects a directory managed by another backend', () async {
    await AiLspManagedInstallService.writeManifest(
      rootPath: temporaryDirectory.path,
      language: 'dart',
      backend: _otherBackend,
      version: '1.0.0',
    );
    await File('${temporaryDirectory.path}/installed.txt').writeAsString('x');

    expect(await validate(temporaryDirectory.path), contains(_otherBackend.id));
  });

  test('rejects symbolic-link install roots', () async {
    if (Platform.isWindows) {
      return;
    }
    final linkPath =
        '${temporaryDirectory.parent.path}/'
        'openhand-managed-lsp-link-${DateTime.now().microsecondsSinceEpoch}';
    final link = Link(linkPath);
    await link.create(temporaryDirectory.path);
    addTearDown(() async {
      if (await link.exists()) {
        await link.delete();
      }
    });

    expect(await validate(link.path), contains('symbolic link'));
  });

  test(
    'manifest cache refreshes asynchronously and rejects corruption',
    () async {
      await AiLspManagedInstallService.writeManifest(
        rootPath: temporaryDirectory.path,
        language: 'dart',
        backend: _backend,
        version: '1.2.3',
      );

      final cached = AiLspManagedInstallService.peekManifest(
        temporaryDirectory.path,
      );
      expect(cached?.backendId, _backend.id);
      expect(cached?.version, '1.2.3');

      await File(
        AiLspManagedInstallManifest.manifestPathForRoot(
          temporaryDirectory.path,
        ),
      ).writeAsString('{invalid');
      expect(
        (await AiLspManagedInstallService.readManifest(
          temporaryDirectory.path,
        ))?.version,
        '1.2.3',
      );
      expect(
        await AiLspManagedInstallService.readManifest(
          temporaryDirectory.path,
          forceRefresh: true,
        ),
        isNull,
      );
      expect(
        AiLspManagedInstallService.peekManifest(temporaryDirectory.path),
        isNull,
      );
    },
  );

  test('managed deletion clears the manifest cache', () async {
    await AiLspManagedInstallService.writeManifest(
      rootPath: temporaryDirectory.path,
      language: 'dart',
      backend: _backend,
      version: 'latest',
    );

    await AiLspManagedInstallService.deleteManagedInstall(
      temporaryDirectory.path,
    );

    expect(await temporaryDirectory.exists(), isFalse);
    expect(
      AiLspManagedInstallService.peekManifest(temporaryDirectory.path),
      isNull,
    );
  });
}
