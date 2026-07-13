import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_lsp_backend_catalog.dart';
import '../../model/ai_lsp_language_settings.dart';

const String _managedInstallManifestFileName =
    '.openhand-lsp-managed-install.json';
const int _managedInstallManifestMaxBytes = 64 * 1024;

class AiLspManagedInstallPlan {
  const AiLspManagedInstallPlan({
    required this.shellCommand,
    required this.previewCommand,
    required this.installRootPath,
  });

  final String shellCommand;
  final String previewCommand;
  final String installRootPath;
}

class AiLspManagedInstallManifest {
  const AiLspManagedInstallManifest({
    required this.backendId,
    required this.language,
    required this.version,
    required this.installKind,
    required this.installRootPath,
    required this.installedAt,
  });

  final String backendId;
  final String language;
  final String version;
  final String installKind;
  final String installRootPath;
  final DateTime installedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'backend_id': backendId,
      'language': language,
      'version': version,
      'install_kind': installKind,
      'install_root_path': installRootPath,
      'installed_at': installedAt.toUtc().toIso8601String(),
      'managed_by': 'openhand',
    };
  }

  static String manifestPathForRoot(String rootPath) {
    return p.join(rootPath, _managedInstallManifestFileName);
  }

  static AiLspManagedInstallManifest? tryRead(String rootPath) {
    try {
      final normalizedRoot = OpenHandPaths.normalizeOptionalPath(rootPath);
      if (normalizedRoot.isEmpty) {
        return null;
      }
      final manifestFile = File(manifestPathForRoot(normalizedRoot));
      if (!manifestFile.existsSync()) {
        return null;
      }
      final decoded = jsonDecode(
        readBoundedFileStringSync(
          manifestFile,
          maxBytes: _managedInstallManifestMaxBytes,
        ),
      );
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      if (optionalStringFromValue(decoded['managed_by']) != 'openhand') {
        return null;
      }
      return AiLspManagedInstallManifest(
        backendId: stringFromValue(decoded['backend_id']),
        language: stringFromValue(decoded['language']),
        version: stringFromValue(decoded['version']),
        installKind: stringFromValue(decoded['install_kind']),
        installRootPath:
            optionalStringFromValue(decoded['install_root_path']) ??
            normalizedRoot,
        installedAt:
            utcDateTimeFromValue(decoded['installed_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    } catch (_) {
      return null;
    }
  }
}

abstract final class AiLspManagedInstallService {
  static final String _currentArchitecture = _detectArchitecture();

  static bool supportsManagedInstall(AiLspBackendDescriptor backend) {
    return switch (backend.install.kind) {
      AiLspManagedInstallKind.none => false,
      AiLspManagedInstallKind.npmLocal => true,
      AiLspManagedInstallKind.pythonVenv => !Platform.isWindows,
      AiLspManagedInstallKind.gemLocal => !Platform.isWindows,
      AiLspManagedInstallKind.goInstall => !Platform.isWindows,
      AiLspManagedInstallKind.directDownload => _supportsDirectDownloadBackend(
        backend.id,
      ),
    };
  }

  static AiLspManagedInstallManifest? readManifest(String rootPath) {
    return AiLspManagedInstallManifest.tryRead(rootPath);
  }

  static String? validateInstallRoot({
    required String language,
    required AiLspBackendDescriptor backend,
    required AiLspLanguageSettings settings,
  }) {
    if (!supportsManagedInstall(backend)) {
      return 'This backend does not support in-app managed installation on the current platform.';
    }
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(
      settings.rootPath,
    );
    if (normalizedRoot.isEmpty) {
      return 'Choose an install root before starting the download.';
    }
    final entityType = FileSystemEntity.typeSync(
      normalizedRoot,
      followLinks: false,
    );
    if (entityType == FileSystemEntityType.file) {
      return 'The selected install root points to a file instead of a directory.';
    }
    if (_isDangerousInstallRoot(normalizedRoot, language: language)) {
      return 'Choose a dedicated subdirectory for this LSP install instead of a shared or top-level folder.';
    }
    final manifest = readManifest(normalizedRoot);
    final directory = Directory(normalizedRoot);
    if (!directory.existsSync()) {
      return null;
    }
    final entries = directory.listSync(followLinks: false);
    final nonManifestEntries = entries
        .where(
          (entry) => p.basename(entry.path) != _managedInstallManifestFileName,
        )
        .toList(growable: false);
    if (nonManifestEntries.isEmpty) {
      return null;
    }
    if (manifest == null) {
      return 'The selected folder is not empty. Use an empty folder or an existing OpenHand-managed LSP install root.';
    }
    if (manifest.backendId != backend.id) {
      return 'The selected folder is already managed for ${manifest.backendId}. Pick a different folder or clean the existing install first.';
    }
    return null;
  }

  static Future<void> writeManifest({
    required String rootPath,
    required String language,
    required AiLspBackendDescriptor backend,
    required String version,
  }) async {
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(rootPath);
    if (normalizedRoot.isEmpty) {
      return;
    }
    await Directory(normalizedRoot).create(recursive: true);
    final manifest = AiLspManagedInstallManifest(
      backendId: backend.id,
      language: normalizeAiLspLanguage(language),
      version: nullIfBlank(version) ?? 'latest',
      installKind: backend.install.kind.name,
      installRootPath: normalizedRoot,
      installedAt: DateTime.now().toUtc(),
    );
    await writeFileAtomically(
      File(AiLspManagedInstallManifest.manifestPathForRoot(normalizedRoot)),
      jsonEncode(manifest.toJson()),
    );
  }

  static Future<void> deleteManagedInstall(String rootPath) async {
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(rootPath);
    final manifest = readManifest(normalizedRoot);
    if (manifest == null) {
      throw StateError(
        'The selected folder is not an OpenHand-managed LSP install.',
      );
    }
    final directory = Directory(normalizedRoot);
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }

  static AiLspManagedInstallPlan? buildInstallPlan(
    AiLspBackendDescriptor backend,
    AiLspLanguageSettings settings,
  ) {
    final installRootPath = OpenHandPaths.normalizeOptionalPath(
      settings.rootPath,
    );
    if (installRootPath.isEmpty || !supportsManagedInstall(backend)) {
      return null;
    }
    final version = settings.normalizedVersion;
    final sdkPath = OpenHandPaths.normalizeOptionalPath(settings.sdkPath);
    return switch (backend.install.kind) {
      AiLspManagedInstallKind.none => null,
      AiLspManagedInstallKind.npmLocal => _buildNpmLocalPlan(
        backend,
        installRootPath,
        version,
        sdkPath: sdkPath,
      ),
      AiLspManagedInstallKind.pythonVenv => _buildPythonVenvPlan(
        backend,
        installRootPath,
        version,
        sdkPath: sdkPath,
      ),
      AiLspManagedInstallKind.gemLocal => _buildGemLocalPlan(
        backend,
        installRootPath,
        version,
        sdkPath: sdkPath,
      ),
      AiLspManagedInstallKind.goInstall => _buildGoInstallPlan(
        backend,
        installRootPath,
        version,
        sdkPath: sdkPath,
      ),
      AiLspManagedInstallKind.directDownload => _buildDirectDownloadPlan(
        backend,
        installRootPath,
        version,
      ),
    };
  }

  static bool _supportsDirectDownloadBackend(String backendId) {
    return switch (backendId) {
      'dart-analysis-server' => _dartSdkAssetName() != null,
      'rust-analyzer' => _rustAnalyzerAssetName() != null,
      'jdtls' => !Platform.isWindows,
      'kotlin-lsp' => !Platform.isWindows,
      'clangd' => _clangdArchiveName('22.1.3') != null,
      'omnisharp' || 'omnisharp-lowercase' => _omnisharpArchiveName() != null,
      'lua-language-server' => _luaLsArchiveName() != null,
      'elixir-ls' => !Platform.isWindows,
      'terraform-ls' => _terraformLsArchiveName() != null,
      'tinymist' => _tinymistAssetName() != null,
      'clojure-lsp' => _clojureLspAssetName() != null,
      _ => false,
    };
  }

  static bool _isDangerousInstallRoot(
    String normalizedRoot, {
    required String language,
  }) {
    final home = OpenHandPaths.homeDirectoryPath();
    final openhandRoot = p.join(home, '.openhand');
    final sharedLspRoot = OpenHandPaths.defaultLspDirectoryPath();
    final languageRoot = OpenHandPaths.defaultLspDirectoryPathForLanguage(
      language,
    );
    final filesystemRoot = p.rootPrefix(normalizedRoot);
    return p.equals(normalizedRoot, filesystemRoot) ||
        p.equals(normalizedRoot, home) ||
        p.equals(normalizedRoot, openhandRoot) ||
        p.equals(normalizedRoot, sharedLspRoot) ||
        nullIfBlank(normalizedRoot) == null ||
        p.equals(normalizedRoot, languageRoot) == false &&
            p.equals(normalizedRoot, p.dirname(languageRoot)) &&
            p.basename(normalizedRoot) == p.basename(sharedLspRoot);
  }

  static AiLspManagedInstallPlan _buildNpmLocalPlan(
    AiLspBackendDescriptor backend,
    String installRootPath,
    String version, {
    String sdkPath = '',
  }) {
    final packageSpecs = <String>[
      ...backend.install.versionedPackages.map(
        (packageName) =>
            version == 'latest' ? packageName : '$packageName@$version',
      ),
      ...backend.install.additionalPackages,
    ];
    if (Platform.isWindows) {
      final sdkPathPrefix = sdkPath.isNotEmpty
          ? 'set "PATH=${sdkPath.replaceAll('/', '\\')}\\bin;%PATH%" && '
          : '';
      final shellCommand = [
        '${sdkPathPrefix}rmdir /s /q ${_quoteWindows(installRootPath)} 2>nul',
        'mkdir ${_quoteWindows(installRootPath)}',
        'npm install --no-fund --no-audit --prefix ${_quoteWindows(installRootPath)} ${packageSpecs.map(_quoteWindows).join(' ')}',
      ].join(' && ');
      return AiLspManagedInstallPlan(
        shellCommand: shellCommand,
        previewCommand:
            'npm install --prefix ${OpenHandPaths.shortenHomePath(installRootPath)} ${packageSpecs.join(' ')}',
        installRootPath: installRootPath,
      );
    }
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['npm'],
            sdkPath: sdkPath,
          )
          ..add(
            'npm install --no-fund --no-audit --prefix "\$ROOT" ${packageSpecs.map(_quotePosix).join(' ')}',
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'npm install --prefix ${OpenHandPaths.shortenHomePath(installRootPath)} ${packageSpecs.join(' ')}',
      installRootPath: installRootPath,
    );
  }

  static AiLspManagedInstallPlan? _buildPythonVenvPlan(
    AiLspBackendDescriptor backend,
    String installRootPath,
    String version, {
    String sdkPath = '',
  }) {
    if (Platform.isWindows) {
      return null;
    }
    final packageSpecs = backend.install.versionedPackages
        .map(
          (packageName) =>
              version == 'latest' ? packageName : '$packageName==$version',
        )
        .toList(growable: false);
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['python3'],
            sdkPath: sdkPath,
          )
          ..add(r'python3 -m venv "$ROOT/.venv"')
          ..add(r'"$ROOT/.venv/bin/python" -m pip install --upgrade pip')
          ..add(
            '"\$ROOT/.venv/bin/python" -m pip install ${packageSpecs.map(_quotePosix).join(' ')}',
          )
          ..add(r'mkdir -p "$ROOT/bin"')
          ..addAll(
            _posixWrapperCommands(
              rootPath: installRootPath,
              executableName: backend.executable,
              bodyLines: const <String>[r'exec "$ROOT/.venv/bin/pylsp" "$@"'],
            ),
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'python3 -m venv ${OpenHandPaths.shortenHomePath(installRootPath)}/.venv && pip install ${packageSpecs.join(' ')}',
      installRootPath: installRootPath,
    );
  }

  static AiLspManagedInstallPlan? _buildGemLocalPlan(
    AiLspBackendDescriptor backend,
    String installRootPath,
    String version, {
    String sdkPath = '',
  }) {
    if (Platform.isWindows) {
      return null;
    }
    final gemSpec = backend.install.versionedPackages.first;
    final versionArg = version == 'latest' ? '' : ' -v ${_quotePosix(version)}';
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['gem'],
            sdkPath: sdkPath,
          )
          ..add(r'mkdir -p "$ROOT/bin" "$ROOT/gems"')
          ..add(
            'gem install --no-document --install-dir "\$ROOT/gems" ${_quotePosix(gemSpec)}$versionArg',
          )
          ..addAll(
            _posixWrapperCommands(
              rootPath: installRootPath,
              executableName: backend.executable,
              bodyLines: <String>[
                r'export GEM_HOME="$ROOT/gems"',
                r'export GEM_PATH="$ROOT/gems"',
                'exec "\$ROOT/gems/bin/${backend.executable}" "\$@"',
              ],
            ),
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'gem install --install-dir ${OpenHandPaths.shortenHomePath(installRootPath)}/gems $gemSpec${version == 'latest' ? '' : ' -v $version'}',
      installRootPath: installRootPath,
    );
  }

  static AiLspManagedInstallPlan? _buildGoInstallPlan(
    AiLspBackendDescriptor backend,
    String installRootPath,
    String version, {
    String sdkPath = '',
  }) {
    if (Platform.isWindows) {
      return null;
    }
    final module = backend.install.versionedPackages.first;
    final resolvedVersion = version == 'latest'
        ? 'latest'
        : (version.startsWith('v') ? version : 'v$version');
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['go'],
            sdkPath: sdkPath,
          )
          ..addAll(<String>[
            if (sdkPath.isNotEmpty) 'export GOROOT=${_quotePosix(sdkPath)}',
          ])
          ..add(r'mkdir -p "$ROOT/bin"')
          ..add(
            'GOBIN="\$ROOT/bin" go install ${_quotePosix('$module@$resolvedVersion')}',
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'GOBIN=${OpenHandPaths.shortenHomePath(installRootPath)}/bin go install $module@$resolvedVersion',
      installRootPath: installRootPath,
    );
  }

  static AiLspManagedInstallPlan? _buildDirectDownloadPlan(
    AiLspBackendDescriptor backend,
    String installRootPath,
    String version,
  ) {
    return switch (backend.id) {
      'dart-analysis-server' => _buildDartSdkPlan(installRootPath, version),
      'rust-analyzer' => _buildRustAnalyzerPlan(installRootPath, version),
      'jdtls' => _buildJdtlsPlan(installRootPath, version),
      'kotlin-lsp' => _buildKotlinLspPlan(installRootPath, version),
      'clangd' => _buildClangdPlan(installRootPath, version),
      'omnisharp' ||
      'omnisharp-lowercase' => _buildOmnisharpPlan(installRootPath, version),
      'lua-language-server' => _buildLuaLsPlan(installRootPath, version),
      'elixir-ls' => _buildElixirLsPlan(installRootPath, version),
      'terraform-ls' => _buildTerraformLsPlan(installRootPath, version),
      'tinymist' => _buildTinymistPlan(installRootPath, version),
      'clojure-lsp' => _buildClojureLspPlan(installRootPath, version),
      _ => null,
    };
  }

  static AiLspManagedInstallPlan? _buildDartSdkPlan(
    String installRootPath,
    String version,
  ) {
    if (Platform.isWindows) {
      return null;
    }
    final assetName = _dartSdkAssetName();
    if (assetName == null) {
      return null;
    }
    final downloadUrl = version == 'latest'
        ? 'https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/$assetName'
        : 'https://storage.googleapis.com/dart-archive/channels/stable/release/$version/sdk/$assetName';
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['curl', 'unzip'],
          )
          ..add(r'ARCHIVE="$TMP_DIR/dart-sdk.zip"')
          ..add('curl -fL ${_quotePosix(downloadUrl)} -o "\$ARCHIVE"')
          ..add(r'mkdir -p "$ROOT/bin"')
          ..add(r'unzip -q "$ARCHIVE" -d "$ROOT"')
          ..addAll(
            _posixWrapperCommands(
              rootPath: installRootPath,
              executableName: 'dart',
              bodyLines: const <String>[r'exec "$ROOT/dart-sdk/bin/dart" "$@"'],
            ),
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'Download Dart SDK into ${OpenHandPaths.shortenHomePath(installRootPath)} and expose dart via ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
      installRootPath: installRootPath,
    );
  }

  static AiLspManagedInstallPlan? _buildRustAnalyzerPlan(
    String installRootPath,
    String version,
  ) {
    if (Platform.isWindows) {
      return null;
    }
    final assetName = _rustAnalyzerAssetName();
    if (assetName == null) {
      return null;
    }
    final downloadUrl = version == 'latest'
        ? 'https://github.com/rust-lang/rust-analyzer/releases/latest/download/$assetName'
        : 'https://github.com/rust-lang/rust-analyzer/releases/download/$version/$assetName';
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['curl', 'gunzip'],
          )
          ..add(r'ARCHIVE="$TMP_DIR/rust-analyzer-asset"')
          ..add(r'mkdir -p "$ROOT/bin"')
          ..add('curl -fL ${_quotePosix(downloadUrl)} -o "\$ARCHIVE"')
          ..add(r'gunzip -c "$ARCHIVE" > "$ROOT/bin/rust-analyzer"')
          ..add(r'chmod +x "$ROOT/bin/rust-analyzer"')
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'Download rust-analyzer from the official GitHub release into ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
      installRootPath: installRootPath,
    );
  }

  static AiLspManagedInstallPlan? _buildJdtlsPlan(
    String installRootPath,
    String version,
  ) {
    if (Platform.isWindows) {
      return null;
    }
    final downloadUrl = version == 'latest'
        ? 'https://www.eclipse.org/downloads/download.php?file=/jdtls/snapshots/jdt-language-server-latest.tar.gz&r=1'
        : 'https://www.eclipse.org/downloads/download.php?file=/jdtls/snapshots/jdt-language-server-$version.tar.gz&r=1';
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['curl', 'tar'],
          )
          ..add(r'ARCHIVE="$TMP_DIR/jdtls.tar.gz"')
          ..add(r'mkdir -p "$ROOT/server" "$ROOT/bin"')
          ..add('curl -fL ${_quotePosix(downloadUrl)} -o "\$ARCHIVE"')
          ..add(r'tar -xzf "$ARCHIVE" --strip-components=1 -C "$ROOT/server"')
          ..addAll(
            _posixWrapperCommands(
              rootPath: installRootPath,
              executableName: 'jdtls',
              bodyLines: const <String>[r'exec "$ROOT/server/bin/jdtls" "$@"'],
            ),
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'Download Eclipse JDTLS into ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))} and expose jdtls via ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
      installRootPath: installRootPath,
    );
  }

  static AiLspManagedInstallPlan? _buildKotlinLspPlan(
    String installRootPath,
    String version,
  ) {
    if (Platform.isWindows) {
      return null;
    }
    final downloadUrl = version == 'latest'
        ? 'https://github.com/fwcd/kotlin-language-server/releases/latest/download/server.zip'
        : 'https://github.com/fwcd/kotlin-language-server/releases/download/$version/server.zip';
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['curl', 'unzip'],
          )
          ..add(r'ARCHIVE="$TMP_DIR/kotlin-language-server.zip"')
          ..add(r'mkdir -p "$ROOT/server" "$ROOT/bin"')
          ..add('curl -fL ${_quotePosix(downloadUrl)} -o "\$ARCHIVE"')
          ..add(r'unzip -q "$ARCHIVE" -d "$ROOT/server"')
          ..addAll(
            _posixWrapperCommands(
              rootPath: installRootPath,
              executableName: 'kotlin-lsp',
              bodyLines: const <String>[
                r'for candidate in "$ROOT/server/bin/kotlin-language-server" "$ROOT/server/server/bin/kotlin-language-server" "$ROOT/server/bin/kotlin-lsp"; do',
                r'  if [ -x "$candidate" ]; then',
                r'    exec "$candidate" "$@"',
                r'  fi',
                r'done',
                r'echo "OpenHand: Kotlin language server executable was not found after installation." >&2',
                r'exit 1',
              ],
            ),
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'Download Kotlin Language Server into ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))} and expose kotlin-lsp via ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
      installRootPath: installRootPath,
    );
  }

  static AiLspManagedInstallPlan? _buildClangdPlan(
    String installRootPath,
    String version,
  ) {
    if (Platform.isWindows) {
      return null;
    }
    final resolvedVersion = version == 'latest' ? '22.1.3' : version;
    final archiveName = _clangdArchiveName(resolvedVersion);
    if (archiveName == null) {
      return null;
    }
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['curl', 'tar'],
          )
          ..add(r'ARCHIVE="$TMP_DIR/clangd.tar.xz"')
          ..add(r'mkdir -p "$ROOT/server" "$ROOT/bin"')
          ..add(
            'curl -fL ${_quotePosix('https://github.com/llvm/llvm-project/releases/download/llvmorg-$resolvedVersion/$archiveName')} -o "\$ARCHIVE"',
          )
          ..add(r'tar -xJf "$ARCHIVE" --strip-components=1 -C "$ROOT/server"')
          ..addAll(
            _posixWrapperCommands(
              rootPath: installRootPath,
              executableName: 'clangd',
              bodyLines: const <String>[r'exec "$ROOT/server/bin/clangd" "$@"'],
            ),
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'Download the official LLVM archive into ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))} and expose clangd via ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
      installRootPath: installRootPath,
    );
  }

  static AiLspManagedInstallPlan? _buildOmnisharpPlan(
    String installRootPath,
    String version,
  ) {
    if (Platform.isWindows) {
      return null;
    }
    final archiveName = _omnisharpArchiveName();
    if (archiveName == null) {
      return null;
    }
    final downloadUrl = version == 'latest'
        ? 'https://github.com/OmniSharp/omnisharp-roslyn/releases/latest/download/$archiveName'
        : 'https://github.com/OmniSharp/omnisharp-roslyn/releases/download/${version.startsWith('v') ? version : 'v$version'}/$archiveName';
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['curl', 'tar'],
          )
          ..add(r'ARCHIVE="$TMP_DIR/omnisharp.tar.gz"')
          ..add(r'mkdir -p "$ROOT/server" "$ROOT/bin"')
          ..add('curl -fL ${_quotePosix(downloadUrl)} -o "\$ARCHIVE"')
          ..add(r'tar -xzf "$ARCHIVE" -C "$ROOT/server"')
          ..addAll(
            _posixWrapperCommands(
              rootPath: installRootPath,
              executableName: 'OmniSharp',
              bodyLines: const <String>[
                r'for candidate in "$ROOT/server/OmniSharp" "$ROOT/server/run" "$ROOT/server/omnisharp"; do',
                r'  if [ -x "$candidate" ]; then',
                r'    exec "$candidate" "$@"',
                r'  fi',
                r'done',
                r'echo "OpenHand: OmniSharp executable was not found after installation." >&2',
                r'exit 1',
              ],
            ),
          )
          ..addAll(
            _posixWrapperCommands(
              rootPath: installRootPath,
              executableName: 'omnisharp',
              bodyLines: const <String>[r'exec "$ROOT/bin/OmniSharp" "$@"'],
            ),
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'Download OmniSharp into ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))} and expose wrappers via ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
      installRootPath: installRootPath,
    );
  }

  // ── Lua Language Server ──

  static AiLspManagedInstallPlan? _buildLuaLsPlan(
    String installRootPath,
    String version,
  ) {
    if (Platform.isWindows) {
      return null;
    }
    final archiveName = _luaLsArchiveName();
    if (archiveName == null) {
      return null;
    }
    final resolvedVersion = version == 'latest' ? '3.13.5' : version;
    final downloadUrl =
        'https://github.com/LuaLS/lua-language-server/releases/download/$resolvedVersion/$archiveName';
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['curl', 'tar'],
          )
          ..add(r'ARCHIVE="$TMP_DIR/lua-ls.tar.gz"')
          ..add(r'mkdir -p "$ROOT/server" "$ROOT/bin"')
          ..add('curl -fL ${_quotePosix(downloadUrl)} -o "\$ARCHIVE"')
          ..add(r'tar -xzf "$ARCHIVE" -C "$ROOT/server"')
          ..addAll(
            _posixWrapperCommands(
              rootPath: installRootPath,
              executableName: 'lua-language-server',
              bodyLines: const <String>[
                r'exec "$ROOT/server/bin/lua-language-server" "$@"',
              ],
            ),
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'Download Lua Language Server into ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))} and expose via ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
      installRootPath: installRootPath,
    );
  }

  // ── ElixirLS ──

  static AiLspManagedInstallPlan? _buildElixirLsPlan(
    String installRootPath,
    String version,
  ) {
    if (Platform.isWindows) {
      return null;
    }
    final downloadUrl = version == 'latest'
        ? 'https://github.com/elixir-lsp/elixir-ls/releases/latest/download/elixir-ls-v0.24.1.zip'
        : 'https://github.com/elixir-lsp/elixir-ls/releases/download/v$version/elixir-ls-v$version.zip';
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['curl', 'unzip'],
          )
          ..add(r'ARCHIVE="$TMP_DIR/elixir-ls.zip"')
          ..add(r'mkdir -p "$ROOT/server" "$ROOT/bin"')
          ..add('curl -fL ${_quotePosix(downloadUrl)} -o "\$ARCHIVE"')
          ..add(r'unzip -q "$ARCHIVE" -d "$ROOT/server"')
          ..add(r'chmod +x "$ROOT/server/language_server.sh"')
          ..addAll(
            _posixWrapperCommands(
              rootPath: installRootPath,
              executableName: 'elixir-ls',
              bodyLines: const <String>[
                r'exec "$ROOT/server/language_server.sh" "$@"',
              ],
            ),
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'Download ElixirLS into ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))} and expose via ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
      installRootPath: installRootPath,
    );
  }

  // ── Terraform LS ──

  static AiLspManagedInstallPlan? _buildTerraformLsPlan(
    String installRootPath,
    String version,
  ) {
    if (Platform.isWindows) {
      return null;
    }
    final archiveName = _terraformLsArchiveName();
    if (archiveName == null) {
      return null;
    }
    final resolvedVersion = version == 'latest' ? '0.34.3' : version;
    final downloadUrl =
        'https://releases.hashicorp.com/terraform-ls/$resolvedVersion/$archiveName';
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['curl', 'unzip'],
          )
          ..add(r'ARCHIVE="$TMP_DIR/terraform-ls.zip"')
          ..add(r'mkdir -p "$ROOT/bin"')
          ..add('curl -fL ${_quotePosix(downloadUrl)} -o "\$ARCHIVE"')
          ..add(r'unzip -q "$ARCHIVE" -d "$ROOT/bin"')
          ..add(r'chmod +x "$ROOT/bin/terraform-ls"')
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'Download Terraform LS into ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
      installRootPath: installRootPath,
    );
  }

  // ── Tinymist (Typst) ──

  static AiLspManagedInstallPlan? _buildTinymistPlan(
    String installRootPath,
    String version,
  ) {
    if (Platform.isWindows) {
      return null;
    }
    final assetName = _tinymistAssetName();
    if (assetName == null) {
      return null;
    }
    final resolvedVersion = version == 'latest'
        ? 'latest'
        : (version.startsWith('v') ? version : 'v$version');
    final downloadUrl = resolvedVersion == 'latest'
        ? 'https://github.com/Myriad-Dreamin/tinymist/releases/latest/download/$assetName'
        : 'https://github.com/Myriad-Dreamin/tinymist/releases/download/$resolvedVersion/$assetName';
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['curl'],
          )
          ..add(r'mkdir -p "$ROOT/bin"')
          ..add('curl -fL ${_quotePosix(downloadUrl)} -o "\$ROOT/bin/tinymist"')
          ..add(r'chmod +x "$ROOT/bin/tinymist"')
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'Download Tinymist into ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
      installRootPath: installRootPath,
    );
  }

  // ── Clojure LSP ──

  static AiLspManagedInstallPlan? _buildClojureLspPlan(
    String installRootPath,
    String version,
  ) {
    if (Platform.isWindows) {
      return null;
    }
    final assetName = _clojureLspAssetName();
    if (assetName == null) {
      return null;
    }
    final resolvedVersion = version == 'latest'
        ? 'latest'
        : (version.startsWith('2') ? version : version);
    final downloadUrl = resolvedVersion == 'latest'
        ? 'https://github.com/clojure-lsp/clojure-lsp/releases/latest/download/$assetName'
        : 'https://github.com/clojure-lsp/clojure-lsp/releases/download/$resolvedVersion/$assetName';
    final lines =
        _posixInstallPreamble(
            installRootPath,
            requiredCommands: const <String>['curl', 'unzip'],
          )
          ..add(r'ARCHIVE="$TMP_DIR/clojure-lsp.zip"')
          ..add(r'mkdir -p "$ROOT/bin"')
          ..add('curl -fL ${_quotePosix(downloadUrl)} -o "\$ARCHIVE"')
          ..add(r'unzip -q "$ARCHIVE" -d "$ROOT/bin"')
          ..add(r'chmod +x "$ROOT/bin/clojure-lsp"')
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          'Download Clojure LSP into ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
      installRootPath: installRootPath,
    );
  }

  static List<String> _posixInstallPreamble(
    String installRootPath, {
    required List<String> requiredCommands,
    String sdkPath = '',
  }) {
    return <String>[
      'set -eu',
      if (sdkPath.isNotEmpty)
        'export PATH=${_quotePosix('$sdkPath/bin')}:"\$PATH"',
      ...requiredCommands.map(
        (command) =>
            'command -v $command >/dev/null 2>&1 || { echo "Missing required command: $command" >&2; exit 127; }',
      ),
      'ROOT=${_quotePosix(installRootPath)}',
      r'TMP_DIR="$(mktemp -d)"',
      'SUCCESS=0',
      'cleanup() {',
      r'  rm -rf "$TMP_DIR"',
      r'  if [ "$SUCCESS" -ne 1 ]; then',
      r'    rm -rf "$ROOT"',
      '  fi',
      '}',
      'trap cleanup EXIT',
      r'rm -rf "$ROOT"',
      r'mkdir -p "$ROOT"',
    ];
  }

  static List<String> _posixWrapperCommands({
    required String rootPath,
    required String executableName,
    required List<String> bodyLines,
  }) {
    final wrapperPath = p.join(rootPath, 'bin', executableName);
    return <String>[
      'cat > ${_quotePosix(wrapperPath)} <<\'EOF\'',
      '#!/bin/sh',
      'set -eu',
      r'ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"',
      ...bodyLines,
      'EOF',
      'chmod +x ${_quotePosix(wrapperPath)}',
    ];
  }

  static String? _dartSdkAssetName() {
    if (Platform.isMacOS) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'dartsdk-macos-arm64-release.zip',
        'x64' || 'x86_64' || 'amd64' => 'dartsdk-macos-x64-release.zip',
        _ => null,
      };
    }
    if (Platform.isLinux) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'dartsdk-linux-arm64-release.zip',
        'x64' || 'x86_64' || 'amd64' => 'dartsdk-linux-x64-release.zip',
        _ => null,
      };
    }
    return null;
  }

  static String? _rustAnalyzerAssetName() {
    if (Platform.isMacOS) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'rust-analyzer-aarch64-apple-darwin.gz',
        'x64' || 'x86_64' || 'amd64' => 'rust-analyzer-x86_64-apple-darwin.gz',
        _ => null,
      };
    }
    if (Platform.isLinux) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'rust-analyzer-aarch64-unknown-linux-gnu.gz',
        'x64' ||
        'x86_64' ||
        'amd64' => 'rust-analyzer-x86_64-unknown-linux-gnu.gz',
        _ => null,
      };
    }
    return null;
  }

  static String? _omnisharpArchiveName() {
    if (Platform.isMacOS) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'omnisharp-osx-arm64-net6.0.tar.gz',
        'x64' || 'x86_64' || 'amd64' => 'omnisharp-osx-x64-net6.0.tar.gz',
        _ => null,
      };
    }
    if (Platform.isLinux) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'omnisharp-linux-arm64-net6.0.tar.gz',
        'x64' || 'x86_64' || 'amd64' => 'omnisharp-linux-x64-net6.0.tar.gz',
        _ => null,
      };
    }
    return null;
  }

  static String? _clangdArchiveName(String version) {
    if (Platform.isMacOS) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'LLVM-$version-macOS-ARM64.tar.xz',
        _ => null,
      };
    }
    if (Platform.isLinux) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'LLVM-$version-Linux-ARM64.tar.xz',
        'x64' || 'x86_64' || 'amd64' => 'LLVM-$version-Linux-X64.tar.xz',
        _ => null,
      };
    }
    return null;
  }

  // ── Lua Language Server archive names ──

  static String? _luaLsArchiveName() {
    if (Platform.isMacOS) {
      return switch (_currentArchitecture) {
        'arm64' ||
        'aarch64' => 'lua-language-server-3.13.5-darwin-arm64.tar.gz',
        'x64' ||
        'x86_64' ||
        'amd64' => 'lua-language-server-3.13.5-darwin-x64.tar.gz',
        _ => null,
      };
    }
    if (Platform.isLinux) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'lua-language-server-3.13.5-linux-arm64.tar.gz',
        'x64' ||
        'x86_64' ||
        'amd64' => 'lua-language-server-3.13.5-linux-x64.tar.gz',
        _ => null,
      };
    }
    return null;
  }

  // ── Terraform LS archive names ──

  static String? _terraformLsArchiveName() {
    if (Platform.isMacOS) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'terraform-ls_0.34.3_darwin_arm64.zip',
        'x64' || 'x86_64' || 'amd64' => 'terraform-ls_0.34.3_darwin_amd64.zip',
        _ => null,
      };
    }
    if (Platform.isLinux) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'terraform-ls_0.34.3_linux_arm64.zip',
        'x64' || 'x86_64' || 'amd64' => 'terraform-ls_0.34.3_linux_amd64.zip',
        _ => null,
      };
    }
    return null;
  }

  // ── Tinymist (Typst LSP) asset names ──

  static String? _tinymistAssetName() {
    if (Platform.isMacOS) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'tinymist-darwin-arm64',
        'x64' || 'x86_64' || 'amd64' => 'tinymist-darwin-x64',
        _ => null,
      };
    }
    if (Platform.isLinux) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'tinymist-linux-arm64',
        'x64' || 'x86_64' || 'amd64' => 'tinymist-linux-x64',
        _ => null,
      };
    }
    return null;
  }

  // ── Clojure LSP asset names ──

  static String? _clojureLspAssetName() {
    if (Platform.isMacOS) {
      return 'clojure-lsp-native-macos-amd64.zip';
    }
    if (Platform.isLinux) {
      return switch (_currentArchitecture) {
        'arm64' || 'aarch64' => 'clojure-lsp-native-linux-aarch64.zip',
        'x64' || 'x86_64' || 'amd64' => 'clojure-lsp-native-linux-amd64.zip',
        _ => null,
      };
    }
    return null;
  }

  static String _detectArchitecture() {
    final candidates = <String>[
      Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '',
      Platform.environment['PROCESSOR_ARCHITEW6432'] ?? '',
      Platform.environment['HOSTTYPE'] ?? '',
      Platform.environment['MACHTYPE'] ?? '',
      Platform.environment['HOST'] ?? '',
      Platform.version,
      Platform.resolvedExecutable,
    ];
    for (final raw in candidates) {
      final value = optionalLowercaseStringFromValue(raw);
      if (value == null) continue;
      if (value.contains('arm64') || value.contains('aarch64')) {
        return 'arm64';
      }
      if (value.contains('x86_64') ||
          value.contains('amd64') ||
          value.contains('x64')) {
        return 'x64';
      }
    }
    if (Platform.isMacOS && Directory('/opt/homebrew/bin').existsSync()) {
      return 'arm64';
    }
    return '';
  }

  static String _quotePosix(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  static String _quoteWindows(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}
