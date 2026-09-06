import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/bounded_delete.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_lsp_backend_catalog.dart';
import '../../model/ai_lsp_language_settings.dart';

const String _managedInstallManifestFileName =
    '.openhand-lsp-managed-install.json';
const int _managedInstallManifestMaxBytes = 64 * kBytesPerKiB;
const BoundedDeletePolicy _managedInstallDeletePolicy = BoundedDeletePolicy(
  maxEntries: 500000,
  maxDepth: 256,
  directoryIdleTimeout: Duration(seconds: 5),
  operationTimeout: Duration(seconds: 30),
  totalTimeout: Duration(minutes: 10),
);

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

  static Future<AiLspManagedInstallManifest?> tryRead(String rootPath) async {
    try {
      final normalizedRoot = OpenHandPaths.normalizeOptionalPath(rootPath);
      if (normalizedRoot.isEmpty) {
        return null;
      }
      final manifestFile = File(manifestPathForRoot(normalizedRoot));
      final decoded = jsonDecode(
        await readBoundedFileString(
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
      final backendId = stringFromValue(decoded['backend_id']);
      final language = stringFromValue(decoded['language']);
      final version = stringFromValue(decoded['version']);
      final installKind = stringFromValue(decoded['install_kind']);
      final installRootPath = OpenHandPaths.normalizeOptionalPath(
        optionalStringFromValue(decoded['install_root_path']) ?? normalizedRoot,
      );
      final installedAt = utcDateTimeFromValue(decoded['installed_at']);
      if (backendId.isEmpty ||
          language.isEmpty ||
          version.isEmpty ||
          !AiLspManagedInstallKind.values.any(
            (kind) => kind.name == installKind,
          ) ||
          installKind == AiLspManagedInstallKind.none.name ||
          installedAt == null ||
          !p.isAbsolute(installRootPath) ||
          !p.equals(installRootPath, normalizedRoot)) {
        return null;
      }
      return AiLspManagedInstallManifest(
        backendId: backendId,
        language: language,
        version: version,
        installKind: installKind,
        installRootPath: installRootPath,
        installedAt: installedAt,
      );
    } catch (_) {
      return null;
    }
  }
}

abstract final class AiLspManagedInstallService {
  static final String _currentArchitecture = _detectArchitecture();
  static const String _installRootInspectionError = '无法检查所选安装目录，请确认权限后重试。';
  static const int _minimumInstallRootDepth = 2;
  static const int _manifestCacheMaxEntries = 128;
  static const int _manifestMaxPendingReads = 64;
  static const Duration _manifestCacheTtl = Duration(minutes: 1);
  static final Stopwatch _manifestCacheClock = Stopwatch()..start();
  static final LinkedHashMap<String, _AiLspManifestCacheEntry> _manifestCache =
      LinkedHashMap<String, _AiLspManifestCacheEntry>();
  static final Map<String, Future<AiLspManagedInstallManifest?>>
  _manifestReads = <String, Future<AiLspManagedInstallManifest?>>{};

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

  static AiLspManagedInstallManifest? peekManifest(String rootPath) {
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(rootPath);
    if (normalizedRoot.isEmpty) return null;
    return _readCachedManifest(normalizedRoot).manifest;
  }

  static Future<AiLspManagedInstallManifest?> readManifest(
    String rootPath, {
    bool forceRefresh = false,
  }) {
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(rootPath);
    if (normalizedRoot.isEmpty) {
      return Future<AiLspManagedInstallManifest?>.value();
    }
    final cached = _readCachedManifest(normalizedRoot);
    if (!forceRefresh && cached.found) {
      return Future<AiLspManagedInstallManifest?>.value(cached.manifest);
    }
    final active = _manifestReads[normalizedRoot];
    if (active != null) return active;
    if (_manifestReads.length >= _manifestMaxPendingReads) {
      return forceRefresh
          ? Future<AiLspManagedInstallManifest?>.value()
          : Future<AiLspManagedInstallManifest?>.value(cached.manifest);
    }

    late final Future<AiLspManagedInstallManifest?> tracked;
    tracked = AiLspManagedInstallManifest.tryRead(normalizedRoot)
        .then((manifest) {
          if (identical(_manifestReads[normalizedRoot], tracked)) {
            _storeCachedManifest(normalizedRoot, manifest);
          }
          return manifest;
        })
        .whenComplete(() {
          if (identical(_manifestReads[normalizedRoot], tracked)) {
            _manifestReads.remove(normalizedRoot);
          }
        });
    _manifestReads[normalizedRoot] = tracked;
    return tracked;
  }

  static Future<String?> validateInstallRoot({
    required AiLspBackendDescriptor backend,
    required AiLspLanguageSettings settings,
  }) async {
    if (!supportsManagedInstall(backend)) {
      return '当前后端在此平台不支持应用内托管安装。';
    }
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(
      settings.rootPath,
    );
    if (normalizedRoot.isEmpty) {
      return '开始下载前，请先选择安装目录。';
    }
    if (_isDangerousInstallRoot(normalizedRoot)) {
      return '请选择绝对路径下的专用子目录，不能使用共享目录或顶层目录。';
    }
    late final FileSystemEntityType entityType;
    try {
      entityType = await FileSystemEntity.type(
        normalizedRoot,
        followLinks: false,
      );
    } on FileSystemException {
      return _installRootInspectionError;
    }
    if (entityType != FileSystemEntityType.notFound &&
        entityType != FileSystemEntityType.directory) {
      return '所选安装目录必须是真实目录，不能是文件或符号链接。';
    }
    final manifest = await readManifest(normalizedRoot, forceRefresh: true);
    if (entityType == FileSystemEntityType.notFound) {
      return null;
    }
    late final BoundedDirectoryListing listing;
    try {
      listing = await listDirectoryBounded(
        Directory(normalizedRoot),
        maxEntries: 2,
      );
    } on FileSystemException {
      return _installRootInspectionError;
    }
    final hasNonManifestEntry = listing.entries.any(
      (entry) => p.basename(entry.path) != _managedInstallManifestFileName,
    );
    if (!hasNonManifestEntry && listing.truncated) {
      return '未能完整检查所选安装目录，请选择本地目录或重试。';
    }
    if (!hasNonManifestEntry) {
      return null;
    }
    if (manifest == null) {
      return '所选目录不为空，请使用空目录或现有的 OpenHand 托管 LSP 安装目录。';
    }
    if (manifest.backendId != backend.id) {
      return '所选目录已由 ${manifest.backendId} 托管，请改用其他目录或先清理现有安装。';
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
    if (_isDangerousInstallRoot(normalizedRoot) ||
        !supportsManagedInstall(backend)) {
      throw StateError('LSP 托管安装目录不符合安全要求。');
    }
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
    unawaited(_manifestReads.remove(normalizedRoot));
    _storeCachedManifest(normalizedRoot, manifest);
  }

  static Future<void> deleteManagedInstall(String rootPath) async {
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(rootPath);
    if (_isDangerousInstallRoot(normalizedRoot)) {
      throw StateError('拒绝清理不安全的 LSP 托管安装目录。');
    }
    final entityType = await FileSystemEntity.type(
      normalizedRoot,
      followLinks: false,
    );
    if (entityType != FileSystemEntityType.directory) {
      throw StateError('所选路径不是真实的托管安装目录。');
    }
    final manifest = await readManifest(normalizedRoot, forceRefresh: true);
    if (manifest == null) {
      throw StateError('所选目录不是 OpenHand 托管的 LSP 安装目录。');
    }
    final directory = Directory(normalizedRoot);
    await deletePathBounded(
      directory.path,
      policy: _managedInstallDeletePolicy,
      allowedRoot: p.dirname(directory.path),
    );
    unawaited(_manifestReads.remove(normalizedRoot));
    _storeCachedManifest(normalizedRoot, null);
  }

  static AiLspManagedInstallPlan? buildInstallPlan(
    AiLspBackendDescriptor backend,
    AiLspLanguageSettings settings,
  ) {
    final installRootPath = OpenHandPaths.normalizeOptionalPath(
      settings.rootPath,
    );
    if (_isDangerousInstallRoot(installRootPath) ||
        !supportsManagedInstall(backend)) {
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

  static bool _isDangerousInstallRoot(String normalizedRoot) {
    if (normalizedRoot.isEmpty ||
        normalizedRoot.contains('\u0000') ||
        !p.isAbsolute(normalizedRoot)) {
      return true;
    }
    final home = OpenHandPaths.homeDirectoryPath();
    final openhandRoot = OpenHandPaths.defaultRootDirectoryPath();
    final sharedLspRoot = OpenHandPaths.defaultLspDirectoryPath();
    final currentDirectory = p.normalize(p.absolute(Directory.current.path));
    final systemTemp = p.normalize(p.absolute(Directory.systemTemp.path));
    final filesystemRoot = p.rootPrefix(normalizedRoot);
    if (p.equals(normalizedRoot, filesystemRoot) ||
        p.equals(normalizedRoot, home) ||
        p.equals(normalizedRoot, openhandRoot) ||
        p.equals(normalizedRoot, sharedLspRoot) ||
        p.equals(normalizedRoot, currentDirectory) ||
        p.equals(normalizedRoot, systemTemp)) {
      return true;
    }
    final relative = p.relative(normalizedRoot, from: filesystemRoot);
    return p
            .split(relative)
            .where((segment) => segment.isNotEmpty && segment != '.')
            .length <
        _minimumInstallRootDepth;
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
          '下载 Dart SDK 到 ${OpenHandPaths.shortenHomePath(installRootPath)}，并通过 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))} 提供 dart 可执行文件',
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
          '从 GitHub 官方发行版下载 rust-analyzer 到 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
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
          '下载 Eclipse JDTLS 到 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))}，并通过 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))} 提供 jdtls 可执行文件',
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
                '  fi',
                'done',
                'echo "OpenHand：安装后未找到 Kotlin 语言服务器可执行文件。" >&2',
                'exit 1',
              ],
            ),
          )
          ..add('SUCCESS=1');
    return AiLspManagedInstallPlan(
      shellCommand: lines.join('\n'),
      previewCommand:
          '下载 Kotlin 语言服务器到 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))}，并通过 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))} 提供 kotlin-lsp 可执行文件',
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
          '下载 LLVM 官方压缩包到 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))}，并通过 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))} 提供 clangd 可执行文件',
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
                '  fi',
                'done',
                'echo "OpenHand：安装后未找到 OmniSharp 可执行文件。" >&2',
                'exit 1',
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
          '下载 OmniSharp 到 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))}，并通过 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))} 提供启动包装器',
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
          '下载 Lua 语言服务器到 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))}，并通过 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))} 提供可执行文件',
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
          '下载 ElixirLS 到 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'server'))}，并通过 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))} 提供可执行文件',
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
          '下载 Terraform LS 到 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
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
          '下载 Tinymist 到 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
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
          '下载 Clojure LSP 到 ${OpenHandPaths.shortenHomePath(p.join(installRootPath, 'bin'))}',
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
            'command -v $command >/dev/null 2>&1 || { echo "缺少必需命令：$command" >&2; exit 127; }',
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
    return '';
  }

  static ({bool found, AiLspManagedInstallManifest? manifest})
  _readCachedManifest(String normalizedRoot) {
    final entry = _manifestCache.remove(normalizedRoot);
    if (entry == null) return (found: false, manifest: null);
    if (entry.expiresAtMicroseconds <=
        _manifestCacheClock.elapsedMicroseconds) {
      return (found: false, manifest: null);
    }
    _manifestCache[normalizedRoot] = entry;
    return (found: true, manifest: entry.manifest);
  }

  static void _storeCachedManifest(
    String normalizedRoot,
    AiLspManagedInstallManifest? manifest,
  ) {
    _manifestCache.remove(normalizedRoot);
    _manifestCache[normalizedRoot] = _AiLspManifestCacheEntry(
      manifest: manifest,
      expiresAtMicroseconds:
          _manifestCacheClock.elapsedMicroseconds +
          _manifestCacheTtl.inMicroseconds,
    );
    while (_manifestCache.length > _manifestCacheMaxEntries) {
      _manifestCache.remove(_manifestCache.keys.first);
    }
  }

  static String _quotePosix(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  static String _quoteWindows(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}

final class _AiLspManifestCacheEntry {
  const _AiLspManifestCacheEntry({
    required this.manifest,
    required this.expiresAtMicroseconds,
  });

  final AiLspManagedInstallManifest? manifest;
  final int expiresAtMicroseconds;
}
