import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:openhand/shared/util/text_normalization.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/platform_shell.dart';
import '../../../shared/util/version_compare.dart';
import '../model/plugin_info.dart';
import 'managed_service_defaults.dart';
import 'plugin_environment_probe.dart';
import 'plugin_toolchain_shell.dart';

const String _dockerImageVersionLabel = 'org.opencontainers.image.version';
const String _qdrantStorageDestination = '/qdrant/storage';

String? _dockerImageVersionFromConfig(
  Map<String, Object?> config, {
  String? environmentKey,
}) {
  final labels = stringKeyedMapFromValue(config['Labels']);
  final labeledVersion = nullIfBlank(
    '${labels[_dockerImageVersionLabel] ?? ''}',
  );
  if (labeledVersion != null) return labeledVersion;
  if (environmentKey == null) return null;
  final environment = config['Env'];
  if (environment is! Iterable) return null;
  final prefix = '$environmentKey=';
  for (final entry in environment) {
    final value = '$entry';
    if (value.startsWith(prefix)) {
      return nullIfBlank(value.substring(prefix.length));
    }
  }
  return null;
}

Map<String, Object?> _dockerManifestDescriptor(Map<String, Object?> inspect) {
  return stringKeyedMapFromValue(inspect['ImageManifestDescriptor']);
}

Map<String, Object?>? _dockerInspectMetadataFromDecoded(
  Object? decoded, {
  required String containerName,
  required String dataDestination,
  String? versionEnvironmentKey,
}) {
  if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
    return null;
  }

  final inspect = stringKeyedMapFromValue(decoded.first);
  final state = stringKeyedMapFromValue(inspect['State']);
  final config = stringKeyedMapFromValue(inspect['Config']);
  final networkSettings = stringKeyedMapFromValue(inspect['NetworkSettings']);
  final hostConfig = stringKeyedMapFromValue(inspect['HostConfig']);
  final labels = stringKeyedMapFromValue(config['Labels']);
  final descriptor = _dockerManifestDescriptor(inspect);
  final platform = stringKeyedMapFromValue(descriptor['platform']);
  final running = boolFromValue(state['Running']);
  final metadata = <String, Object?>{
    'runtime_managed': true,
    'docker_daemon_running': true,
    'openhand_managed':
        boolFromValue(labels['openhand.managed']) ||
        boolFromValue(labels['com.openhand.managed']),
    'container_id': '${inspect['Id'] ?? ''}'.trim(),
    'container_name': containerName,
    'container_status': '${state['Status'] ?? ''}'.trim(),
    'running': running,
    'started_at': '${state['StartedAt'] ?? ''}'.trim(),
    'finished_at': '${state['FinishedAt'] ?? ''}'.trim(),
    'restart_count': optionalNonNegativeIntFromValue(state['RestartCount']),
    'exit_code': optionalNonNegativeIntFromValue(state['ExitCode']),
    'image': '${config['Image'] ?? ''}'.trim(),
    'image_id': '${inspect['Image'] ?? ''}'.trim(),
    'image_version': _dockerImageVersionFromConfig(
      config,
      environmentKey: versionEnvironmentKey,
    ),
    'image_manifest_digest': '${descriptor['digest'] ?? ''}'.trim(),
    'image_os': '${platform['os'] ?? inspect['Platform'] ?? ''}'.trim(),
    'image_architecture': '${platform['architecture'] ?? ''}'.trim(),
    'ports': PluginScannerService._formatDockerPorts(networkSettings['Ports']),
    'restart_policy': PluginScannerService._formatRestartPolicy(
      hostConfig['RestartPolicy'],
    ),
    'data_directory': PluginScannerService._extractHostDataDirectory(
      inspect['Mounts'],
      destination: dataDestination,
    ),
  };
  return metadata;
}

Map<String, Object?>? _qdrantInspectMetadataFromDecoded(Object? decoded) {
  final metadata = _dockerInspectMetadataFromDecoded(
    decoded,
    containerName: PluginScannerService.qdrantContainerName,
    dataDestination: _qdrantStorageDestination,
  );
  if (metadata == null) return null;
  return <String, Object?>{
    ...metadata,
    'rest_endpoint': 'http://127.0.0.1:${PluginScannerService.qdrantRestPort}',
    'grpc_endpoint': '127.0.0.1:${PluginScannerService.qdrantGrpcPort}',
  };
}

Map<String, Object?>? _managedDatabaseMetadataFromDecoded(
  Object? decoded, {
  required String containerName,
  required String endpoint,
  required String dataDestination,
  required String versionEnvironmentKey,
}) {
  final metadata = _dockerInspectMetadataFromDecoded(
    decoded,
    containerName: containerName,
    dataDestination: dataDestination,
    versionEnvironmentKey: versionEnvironmentKey,
  );
  if (metadata == null) return null;
  return <String, Object?>{
    ...metadata,
    'service_running': metadata['running'] == true,
    'endpoint': endpoint,
  };
}

/// 扫描本机已安装的插件（NodeJS / Playwright / Python / pip），检测版本与可用性。
///
/// 对于 nvm / pyenv 用户，优先直接解析或借助管理器拿到真实可执行路径，
/// 避免 GUI 应用进程 PATH 与终端不一致的问题。
class PluginScannerService {
  static const String hermesAgentPackageName = 'hermes-agent';
  static const String hermesAgentCommand = 'hermes-agent';
  static const String hermesAgentAltCommand = 'hermes';
  static const String qdrantContainerName =
      ManagedServiceDefaults.qdrantContainerName;
  static const int qdrantRestPort = ManagedServiceDefaults.qdrantRestPort;
  static const int qdrantGrpcPort = ManagedServiceDefaults.qdrantGrpcPort;
  static const int _maxConcurrentScans = 4;
  static const int _nvmAliasMaxBytes = 4 * kBytesPerKiB;
  static final RegExp _nvmMajorAliasPattern = RegExp(r'^v?\d+$');
  static final RegExp _nvmFullVersionAliasPattern = RegExp(
    r'^v?\d+\.\d+\.\d+$',
  );
  static final RegExp _nodeVersionOutputPattern = RegExp(r'v(\d+\.\d+\.\d+)');
  static final RegExp _strictNodeVersionPattern = RegExp(r'^v\d+\.\d+\.\d+$');
  static final RegExp _pyenvVersionPathPattern = RegExp(
    r'/.pyenv/versions/([^/]+)/',
  );
  static final RegExp _brewPythonFormulaPathPattern = RegExp(
    r'/(python(?:@[\d.]+)?)(?:/|$)',
  );
  static final RegExp _semverSearchPattern = RegExp(r'(\d+\.\d+\.\d+)');
  static final RegExp _playwrightVersionPrefixPattern = RegExp(
    r'^Version\s+',
    caseSensitive: false,
  );
  static final RegExp _looseVersionPattern = RegExp(
    r'(\d+(?:\.\d+)+(?:[-+._A-Za-z0-9]*)?)',
  );
  static final RegExp _quotedJavaVersionPattern = RegExp(
    r'version\s+"([^"]+)"',
  );

  final OpenHandSingleFlight<_PythonRuntimeScan?> _pythonRuntimeProbe =
      OpenHandSingleFlight<_PythonRuntimeScan?>();
  final OpenHandKeyedSingleFlight<String, String?> _brewLatestVersionFlights =
      OpenHandKeyedSingleFlight<String, String?>();
  final OpenHandSingleFlight<String?> _latestPipVersionProbe =
      OpenHandSingleFlight<String?>();
  final OpenHandSingleFlight<String?> _latestDingtalkWorkspaceCliVersionProbe =
      OpenHandSingleFlight<String?>();

  Future<T> _runWithFallback<T>({
    required String operation,
    required T fallback,
    required Future<T> Function() operationBody,
  }) async {
    try {
      return await operationBody();
    } catch (error, stack) {
      silentLog('plugin_scanner', operation, error, stack);
      return fallback;
    }
  }

  Future<ProcessResult> _runShellScript(
    String script, {
    String tag = 'plugin_scanner.shell_probe',
    Duration timeout = const Duration(seconds: 15),
  }) {
    return runTrackedProcessOrFailed(
      pluginShellExecutable(),
      ['-c', script],
      timeout: timeout,
      tag: tag,
      environment: pluginProxyEnvironment(),
    );
  }

  /// 通过 shell 执行命令（用于 fnm/volta/brew/pyenv 等场景）。
  Future<ProcessResult> _shellRun(String command) {
    return _runShellScript('${pluginToolchainShellPrefix()}$command');
  }

  Future<ProcessResult> _resolveCommandPath(
    String command, {
    required bool includeNpmGlobalBinFallback,
  }) {
    return _runShellScript(
      pluginToolchainCommandPathScript(
        command,
        includeNpmGlobalBinFallback: includeNpmGlobalBinFallback,
      ),
      tag: 'plugin_scanner.command_path.$command',
    );
  }

  Future<String> _readNvmDefaultAlias() async {
    final nvmDir = pluginNvmDirectoryPath();
    try {
      final aliasFile = File(p.join(nvmDir, 'alias', 'default'));
      final alias = (await readBoundedFileString(
        aliasFile,
        maxBytes: _nvmAliasMaxBytes,
      )).trim();
      if (alias.isNotEmpty) return alias;
    } catch (error, stack) {
      silentLog('plugin_scanner', '读取 nvm 默认别名', error, stack);
    }
    return 'node';
  }

  /// 直接从 nvm 目录结构解析当前默认 Node 版本（不依赖 shell）。
  Future<({String version, String nodeBin, String npmBin})?>
  _resolveNvmDirect() async {
    final nvmDir = pluginNvmDirectoryPath();
    final versionsDir = Directory(p.join(nvmDir, 'versions', 'node'));
    if (!await isDirectoryPath(versionsDir.path, followLinks: true)) {
      return null;
    }

    final versions = <String>[];
    try {
      final listing = await listDirectoryBounded(versionsDir, maxEntries: 256);
      for (final entity in listing.entries) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (name.startsWith('v')) versions.add(name);
        }
      }
    } catch (error, stack) {
      silentLog('plugin_scanner', '列出 nvm 版本', error, stack);
      return null;
    }
    if (versions.isEmpty) return null;
    versions.sort(compareSemanticVersions);

    final alias = await _readNvmDefaultAlias();

    String resolvedVersion;
    if (alias == 'node' || alias == 'stable' || alias == 'current') {
      resolvedVersion = versions.last;
    } else if (alias.startsWith('lts')) {
      resolvedVersion = versions.lastWhere(
        (v) => versionMajorFromText(v)?.isEven ?? false,
        orElse: () => versions.last,
      );
    } else if (_nvmMajorAliasPattern.hasMatch(alias)) {
      final major = alias.replaceFirst('v', '');
      resolvedVersion = versions.lastWhere(
        (v) => v.substring(1).split('.').first == major,
        orElse: () => versions.last,
      );
    } else if (_nvmFullVersionAliasPattern.hasMatch(alias)) {
      resolvedVersion = alias.startsWith('v') ? alias : 'v$alias';
      if (!versions.contains(resolvedVersion)) resolvedVersion = versions.last;
    } else {
      resolvedVersion = versions.last;
    }

    final nodeBin = p.join(
      nvmDir,
      'versions',
      'node',
      resolvedVersion,
      'bin',
      'node',
    );
    final npmBin = p.join(
      nvmDir,
      'versions',
      'node',
      resolvedVersion,
      'bin',
      'npm',
    );
    if (!await isRegularFilePath(nodeBin, followLinks: true)) return null;
    return (version: resolvedVersion, nodeBin: nodeBin, npmBin: npmBin);
  }

  Future<PluginNpmPackageInstallation?> _resolveGlobalNpmPackage(
    String packageName,
  ) async {
    final rootResult = await _shellRun('npm root -g');
    return resolvePluginGlobalNpmPackage(
      exitCode: rootResult.exitCode,
      stdout: rootResult.stdout.toString(),
      packageName: packageName,
    );
  }

  static String? _extractVersion(String output) {
    final match = _nodeVersionOutputPattern.firstMatch(output);
    return match?.group(0);
  }

  static Object? _decodeOptionalJson(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return null;
    }
  }

  Future<String?> _queryLatestNodeVersion({
    required String installedVersion,
    String? releaseHint,
  }) async {
    final major = _extractNodeMajor(installedVersion);
    if (major == null) return null;
    final normalizedHint = (releaseHint ?? '').trim().toLowerCase();
    final preferLts = normalizedHint.startsWith('lts') || major.isEven;

    if (preferLts) {
      final latestLts = await _queryNvmAliasVersion('lts/*');
      if (latestLts != null) return latestLts;
    } else {
      final latestCurrent = await _queryNvmAliasVersion('node');
      if (latestCurrent != null) return latestCurrent;
    }

    final indexVersion = await _queryNodeIndexVersion(preferLts: preferLts);
    if (indexVersion != null) return indexVersion;

    final fallbackAlias = preferLts ? 'lts/*' : 'node';
    return _queryNvmAliasVersion(fallbackAlias);
  }

  Future<String?> _queryNvmAliasVersion(String alias) async {
    final result = await _shellRun('nvm version $alias');
    if (result.exitCode != 0) return null;
    return _extractVersion(result.stdout.toString());
  }

  Future<String?> _queryNodeIndexVersion({required bool preferLts}) async {
    final result = await _shellRun(
      'curl -fsSL https://nodejs.org/dist/index.json',
    );
    if (result.exitCode != 0) return null;
    final decoded = _decodeOptionalJson(result.stdout.toString());
    if (decoded is! List) return null;
    for (final entry in decoded) {
      if (entry is! Map<String, Object?>) continue;
      final version = entry['version'];
      if (version is! String || !_isNodeVersion(version)) continue;
      final lts = entry['lts'];
      final isLts = lts is String && lts.isNotEmpty;
      if (preferLts ? isLts : !isLts) return version;
    }
    return null;
  }

  static int? _extractNodeMajor(String version) {
    return versionMajorFromText(version);
  }

  static bool _isNodeVersion(String value) {
    return _strictNodeVersionPattern.hasMatch(value);
  }

  static String? _pickHigherNodeVersion(
    String installedVersion,
    String? candidateLatestVersion,
  ) {
    if (candidateLatestVersion == null || candidateLatestVersion.isEmpty) {
      return null;
    }
    return compareSemanticVersions(candidateLatestVersion, installedVersion) > 0
        ? candidateLatestVersion
        : null;
  }

  static String? _extractPyenvVersionFromPath(String path) {
    final match = _pyenvVersionPathPattern.firstMatch(path);
    final value = match?.group(1);
    if (value != null && isStrictSemanticVersionText(value)) return value;
    return null;
  }

  static String? _extractBrewPythonFormulaFromPath(String path) {
    final matches = _brewPythonFormulaPathPattern.allMatches(path);
    if (matches.isEmpty) return null;
    return matches.last.group(1);
  }

  Future<bool> _isPyenvAvailable() async {
    if (await pluginPyenvInstallationExists()) return true;
    final result = await _shellRun('command -v pyenv');
    return result.exitCode == 0;
  }

  Future<String?> _queryPyenvLatestVersion(String currentVersion) async {
    final parts = currentVersion.split('.');
    if (parts.length < 2) return null;
    final majorMinor = '${parts[0]}.${parts[1]}';
    final quickResult = await _shellRun(
      'pyenv latest -k $majorMinor 2>/dev/null || true',
    );
    final quickVersion = extractPluginFirstSemver(
      '${quickResult.stdout}\n${quickResult.stderr}',
      prefix: '$majorMinor.',
    );
    if (quickVersion != null) return quickVersion;

    final listResult = await _shellRun('pyenv install --list');
    if (listResult.exitCode != 0) return null;
    final versions = extractPluginStableVersionLines(
      listResult.stdout.toString(),
      prefix: '$majorMinor.',
    );
    if (versions.isEmpty) return null;
    versions.sort(compareSemanticVersions);
    return versions.last;
  }

  Future<String?> _queryBrewLatestVersion(String formula) {
    final normalizedFormula = formula.trim();
    if (normalizedFormula.isEmpty) return Future<String?>.value();
    return _brewLatestVersionFlights.run(
      normalizedFormula,
      () => _queryBrewLatestVersionUncached(normalizedFormula),
    );
  }

  Future<String?> _queryBrewLatestVersionUncached(String formula) async {
    final result = await _shellRun('brew info --json=v2 $formula');
    if (result.exitCode != 0) return null;
    final decoded = _decodeOptionalJson(result.stdout.toString());
    final formulae = decoded is Map<String, Object?>
        ? decoded['formulae']
        : null;
    if (formulae is! List || formulae.isEmpty) return null;
    final item = formulae.first;
    if (item is! Map<String, Object?>) return null;
    final versions = item['versions'];
    if (versions is! Map<String, Object?>) return null;
    final stable = versions['stable'];
    return stable is String && stable.isNotEmpty ? stable : null;
  }

  Future<String?> _queryLatestPipVersion() {
    return _latestPipVersionProbe.run(_queryLatestPipVersionUncached);
  }

  Future<String?> _queryLatestPipVersionUncached() async {
    final result = await _shellRun('curl -fsSL https://pypi.org/pypi/pip/json');
    if (result.exitCode != 0) return null;
    final decoded = _decodeOptionalJson(result.stdout.toString());
    if (decoded is! Map<String, Object?>) return null;
    final info = decoded['info'];
    if (info is! Map<String, Object?>) return null;
    final version = info['version'];
    return version is String && version.isNotEmpty ? version : null;
  }

  Future<String?> _queryLatestPypiVersion(String packageName) async {
    final normalized = packageName.trim();
    if (normalized.isEmpty) return null;
    final result = await _shellRun(
      'curl -fsSL https://pypi.org/pypi/$normalized/json',
    );
    if (result.exitCode != 0) return null;
    final decoded = _decodeOptionalJson(result.stdout.toString());
    if (decoded is! Map<String, Object?>) return null;
    final info = decoded['info'];
    if (info is! Map<String, Object?>) return null;
    final version = info['version'];
    return version is String && version.isNotEmpty ? version : null;
  }

  Future<String?> _queryLatestNpmVersion(String packageName) async {
    final normalized = packageName.trim();
    if (normalized.isEmpty) return null;
    final result = await _shellRun('npm view $normalized version');
    if (result.exitCode != 0) return null;
    final version = extractPluginFirstSemver(result.stdout.toString());
    return version;
  }

  static String? _extractLooseVersion(String output) {
    final match = _looseVersionPattern.firstMatch(output);
    return match?.group(1);
  }

  Future<_ContainerImageUpdateState> _scanContainerImageUpdate({
    required Map<String, Object?> metadata,
    String? versionEnvironmentKey,
  }) async {
    final image = nullIfBlank('${metadata['image'] ?? ''}');
    final containerImageId = nullIfBlank('${metadata['image_id'] ?? ''}');
    final containerManifestDigest = nullIfBlank(
      '${metadata['image_manifest_digest'] ?? ''}',
    );
    final currentVersion = nullIfBlank('${metadata['image_version'] ?? ''}');
    if (image == null) {
      return _ContainerImageUpdateState(
        installedVersion: currentVersion,
        metadata: const <String, Object?>{
          'update_check_error': '容器镜像名称为空，无法检查更新。',
        },
      );
    }

    Map<String, Object?> localImage = const <String, Object?>{};
    final localResult = await _shellRun(
      'docker image inspect ${posixShellQuote(image)}',
    );
    if (localResult.exitCode == 0) {
      final decoded = _decodeOptionalJson(localResult.stdout.toString());
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        localImage = stringKeyedMapFromValue(decoded.first);
      }
    }
    final localImageId = nullIfBlank('${localImage['Id'] ?? ''}');
    final localDescriptor = stringKeyedMapFromValue(localImage['Descriptor']);
    var localDigest = nullIfBlank('${localDescriptor['digest'] ?? ''}');
    final repoDigests = localImage['RepoDigests'];
    if (localDigest == null && repoDigests is Iterable) {
      for (final entry in repoDigests) {
        final value = '$entry';
        final separator = value.lastIndexOf('@');
        if (separator < 0) continue;
        localDigest = nullIfBlank(value.substring(separator + 1));
        if (localDigest != null) break;
      }
    }
    final localConfig = stringKeyedMapFromValue(localImage['Config']);
    final localVersion = _dockerImageVersionFromConfig(
      localConfig,
      environmentKey: versionEnvironmentKey,
    );
    final imageOs = nullIfBlank(
      '${localImage['Os'] ?? metadata['image_os'] ?? ''}',
    );
    final imageArchitecture = nullIfBlank(
      '${localImage['Architecture'] ?? metadata['image_architecture'] ?? ''}',
    );
    final platform = imageOs != null && imageArchitecture != null
        ? '$imageOs/$imageArchitecture'
        : null;

    String? remoteDigest;
    String? remotePlatformDigest;
    String? remoteVersion;
    if (platform != null &&
        RegExp(r'^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$').hasMatch(platform)) {
      final format =
          '{"digest":{{json .Manifest.Digest}},'
          '"config":{{json (index .Image "$platform").Config}}}';
      final remoteResult = await _shellRun(
        'docker buildx imagetools inspect ${posixShellQuote(image)} '
        '--format ${posixShellQuote(format)}',
      );
      if (remoteResult.exitCode == 0) {
        final decoded = _decodeOptionalJson(remoteResult.stdout.toString());
        if (decoded is Map) {
          final remote = stringKeyedMapFromValue(decoded);
          remoteDigest = nullIfBlank('${remote['digest'] ?? ''}');
          remoteVersion = _dockerImageVersionFromConfig(
            stringKeyedMapFromValue(remote['config']),
            environmentKey: versionEnvironmentKey,
          );
        }
      }
    }

    if ((remoteDigest == null || localDigest == null) && platform != null) {
      final manifestResult = await _shellRun(
        'docker manifest inspect ${posixShellQuote(image)}',
      );
      final decoded = manifestResult.exitCode == 0
          ? _decodeOptionalJson(manifestResult.stdout.toString())
          : null;
      final manifest = decoded is Map
          ? stringKeyedMapFromValue(decoded)
          : const <String, Object?>{};
      final manifests = manifest['manifests'];
      if (manifests is Iterable) {
        for (final entry in manifests) {
          if (entry is! Map) continue;
          final descriptor = stringKeyedMapFromValue(entry);
          final remotePlatform = stringKeyedMapFromValue(
            descriptor['platform'],
          );
          if ('${remotePlatform['os'] ?? ''}' == imageOs &&
              '${remotePlatform['architecture'] ?? ''}' == imageArchitecture) {
            remotePlatformDigest = nullIfBlank('${descriptor['digest'] ?? ''}');
            final annotations = stringKeyedMapFromValue(
              descriptor['annotations'],
            );
            remoteVersion ??= nullIfBlank(
              '${annotations[_dockerImageVersionLabel] ?? ''}',
            );
            break;
          }
        }
      }
    }

    final containerBehindLocal =
        containerImageId != null &&
        localImageId != null &&
        containerImageId != localImageId;
    final remoteComparisonKnown =
        remoteDigest != null && localDigest != null ||
        remotePlatformDigest != null && containerManifestDigest != null;
    final remoteChanged =
        remoteDigest != null &&
            localDigest != null &&
            remoteDigest != localDigest ||
        remotePlatformDigest != null &&
            containerManifestDigest != null &&
            remotePlatformDigest != containerManifestDigest;
    final updateAvailable = containerBehindLocal || remoteChanged
        ? true
        : remoteComparisonKnown
        ? false
        : null;
    final targetDigest = remoteDigest ?? remotePlatformDigest ?? localDigest;
    final digestLabel = targetDigest == null
        ? null
        : targetDigest.length > 19
        ? targetDigest.substring(0, 19)
        : targetDigest;

    return _ContainerImageUpdateState(
      installedVersion: currentVersion ?? localVersion,
      latestVersion:
          remoteVersion ??
          (updateAvailable == true
              ? localVersion ?? digestLabel ?? image
              : null),
      updateAvailable: updateAvailable,
      metadata: <String, Object?>{
        if (localDigest != null) 'local_image_digest': localDigest,
        if (remoteDigest != null) 'remote_image_digest': remoteDigest,
        if (remotePlatformDigest != null)
          'remote_platform_image_digest': remotePlatformDigest,
        if (updateAvailable != null) 'image_update_available': updateAvailable,
        if (updateAvailable == null)
          'update_check_error': '无法获取 $image 的远端镜像摘要。',
      },
    );
  }

  static String? _extractJavaVersion(String output) {
    final quoted = _quotedJavaVersionPattern.firstMatch(output);
    if (quoted != null) return quoted.group(1);
    return _extractLooseVersion(output);
  }

  Future<PluginInfo> _scanCommandPlugin({
    required String id,
    required String name,
    required String description,
    required List<String> commands,
    required List<String> versionArgs,
    required String? Function(String output) versionParser,
    String? latestBrewFormula,
    String? latestPypiPackage,
    String? latestNpmPackage,
    List<String> dependencies = const <String>[],
    List<String> dependents = const <String>[],
    bool supportsUninstall = true,
  }) async {
    for (final command in commands) {
      final pathResult = await _resolveCommandPath(
        command,
        includeNpmGlobalBinFallback: latestNpmPackage != null,
      );
      if (pathResult.exitCode != 0) continue;
      final installPath = extractPluginAbsolutePath(
        pathResult.stdout.toString(),
      );
      if (installPath == null || installPath.isEmpty) continue;
      final versionResult = await _shellRun(
        [
          posixShellQuote(installPath),
          ...versionArgs.map(posixShellQuote),
        ].join(' '),
      );
      final output = '${versionResult.stdout}\n${versionResult.stderr}'.trim();
      final version = versionResult.exitCode == 0
          ? versionParser(output)
          : null;
      final latestVersion = latestBrewFormula != null
          ? await _queryBrewLatestVersion(latestBrewFormula)
          : latestPypiPackage != null
          ? await _queryLatestPypiVersion(latestPypiPackage)
          : latestNpmPackage != null
          ? await _queryLatestNpmVersion(latestNpmPackage)
          : null;
      return PluginInfo(
        id: id,
        name: name,
        description: description,
        status: PluginStatus.installed,
        installedVersion: version,
        latestVersion: latestVersion,
        installPath: installPath,
        dependencies: dependencies,
        dependents: dependents,
        supportsUninstall: supportsUninstall,
      );
    }
    return _placeholderById(id);
  }

  static PluginInfo _placeholderById(String id) {
    return switch (id) {
      PluginCatalogIds.nodejs => _nodeNotInstalled,
      PluginCatalogIds.playwright => _playwrightNotInstalled,
      PluginCatalogIds.hermesAgent => _hermesAgentNotInstalled,
      PluginCatalogIds.dingtalkWorkspaceCli =>
        _dingtalkWorkspaceCliNotInstalled,
      PluginCatalogIds.python => _pythonNotInstalled,
      PluginCatalogIds.pip => _pipNotInstalled,
      PluginCatalogIds.java => _javaNotInstalled,
      PluginCatalogIds.frida => _fridaNotInstalled,
      PluginCatalogIds.mitmproxy => _mitmproxyNotInstalled,
      PluginCatalogIds.apktool => _apktoolNotInstalled,
      PluginCatalogIds.jadx => _jadxNotInstalled,
      PluginCatalogIds.radare2 => _radare2NotInstalled,
      PluginCatalogIds.blutter => _blutterNotInstalled,
      PluginCatalogIds.doldrums => _doldrumsNotInstalled,
      PluginCatalogIds.anythingAnalyzer => _anythingAnalyzerNotInstalled,
      PluginCatalogIds.docker => _dockerNotInstalled,
      PluginCatalogIds.qdrant => _qdrantNotInstalled,
      PluginCatalogIds.postgresql => _postgresqlNotInstalled,
      PluginCatalogIds.redis => _redisNotInstalled,
      _ => PluginInfo(
        id: id,
        name: id,
        description: '未检测到该插件',
        status: PluginStatus.notInstalled,
      ),
    };
  }

  Future<_PythonRuntimeScan?> _resolvePyenvPython() async {
    final versionNameResult = await _shellRun('pyenv version-name');
    final selectedVersionName = versionNameResult.exitCode == 0
        ? versionNameResult.stdout
              .toString()
              .trim()
              .split(kInlineWhitespacePattern)
              .first
        : null;
    for (final command in const ['python3', 'python']) {
      final whichResult = await _shellRun('pyenv which $command');
      if (whichResult.exitCode != 0) continue;
      final executable = extractPluginAbsolutePath(
        whichResult.stdout.toString(),
      );
      if (executable == null || executable.isEmpty) continue;
      final versionResult = await runTrackedProcessOrFailed(
        executable,
        ['--version'],
        timeout: const Duration(seconds: 5),
        tag: 'plugin_scanner.python_probe',
        environment: pluginProxyEnvironment(),
      );
      if (versionResult.exitCode != 0) continue;
      final version = extractPythonVersion(
        '${versionResult.stdout}\n${versionResult.stderr}',
      );
      if (version == null) continue;
      final managedPyenvVersion =
          (selectedVersionName != null &&
              isStrictSemanticVersionText(selectedVersionName))
          ? selectedVersionName
          : _extractPyenvVersionFromPath(executable);
      final formula = pluginLooksLikeHomebrewPythonPath(executable)
          ? (_extractBrewPythonFormulaFromPath(executable) ?? 'python')
          : null;
      final source = managedPyenvVersion != null
          ? _PythonRuntimeSource.pyenv
          : formula != null
          ? _PythonRuntimeSource.homebrew
          : pluginLooksLikeSystemPythonPath(executable)
          ? _PythonRuntimeSource.system
          : _PythonRuntimeSource.unknown;
      final latestVersion = switch (source) {
        _PythonRuntimeSource.pyenv => await _queryPyenvLatestVersion(version),
        _PythonRuntimeSource.homebrew => await _queryBrewLatestVersion(
          formula!,
        ),
        _ => null,
      };
      return _PythonRuntimeScan(
        version: version,
        executable: executable,
        latestVersion: latestVersion,
        source: source,
        pyenvVersion: managedPyenvVersion,
        brewFormula: formula,
      );
    }
    return null;
  }

  Future<_PythonRuntimeScan?> _resolveShellPython() async {
    for (final command in const ['python3', 'python']) {
      final versionResult = await _shellRun('$command --version');
      if (versionResult.exitCode != 0) continue;
      final version = extractPythonVersion(
        '${versionResult.stdout}\n${versionResult.stderr}',
      );
      if (version == null) continue;
      final pathResult = await _shellRun('command -v $command');
      final executable = pathResult.exitCode == 0
          ? extractPluginAbsolutePath(pathResult.stdout.toString())
          : null;
      if (executable == null || executable.isEmpty) continue;
      final formula = pluginLooksLikeHomebrewPythonPath(executable)
          ? (_extractBrewPythonFormulaFromPath(executable) ?? 'python')
          : null;
      final source = formula != null
          ? _PythonRuntimeSource.homebrew
          : pluginLooksLikeSystemPythonPath(executable)
          ? _PythonRuntimeSource.system
          : _PythonRuntimeSource.unknown;
      final latestVersion = source == _PythonRuntimeSource.homebrew
          ? await _queryBrewLatestVersion(formula!)
          : null;
      return _PythonRuntimeScan(
        version: version,
        executable: executable,
        latestVersion: latestVersion,
        source: source,
        brewFormula: formula,
      );
    }
    return null;
  }

  Future<_PythonRuntimeScan?> _resolvePythonRuntime() {
    return _pythonRuntimeProbe.run(_resolvePythonRuntimeUncached);
  }

  Future<_PythonRuntimeScan?> _resolvePythonRuntimeUncached() async {
    final pyenvAvailable = await _isPyenvAvailable();
    final runtime = pyenvAvailable
        ? await _resolvePyenvPython()
        : await _resolveShellPython();
    return runtime ?? await _resolveShellPython();
  }

  PluginInfo _pythonInfoFromRuntime(_PythonRuntimeScan? runtime) {
    if (runtime == null) return _pythonNotInstalled;
    return PluginInfo(
      id: PluginCatalogIds.python,
      name: 'Python',
      description: 'Python 运行时环境，用于执行 Python 脚本、库与扩展能力',
      status: PluginStatus.installed,
      installedVersion: runtime.version,
      latestVersion: runtime.latestVersion,
      installPath: runtime.executable,
    );
  }

  Future<PluginInfo> scanNodeJs() async {
    try {
      final nvm = await _resolveNvmDirect();
      if (nvm != null) {
        final versionResult = await runTrackedProcessOrFailed(
          nvm.nodeBin,
          ['--version'],
          timeout: const Duration(seconds: 5),
          environment: pluginProxyEnvironment(),
        );
        final version = versionResult.exitCode == 0
            ? versionResult.stdout.toString().trim()
            : nvm.version;
        final latestVersion = await _queryLatestNodeVersion(
          installedVersion: version,
          releaseHint: await _readNvmDefaultAlias(),
        );
        return PluginInfo(
          id: PluginCatalogIds.nodejs,
          name: 'Node.js',
          description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
          status: PluginStatus.installed,
          installedVersion: version,
          latestVersion: _pickHigherNodeVersion(version, latestVersion),
          installPath: nvm.nodeBin,
          dependents: const <String>[PluginCatalogIds.playwright],
        );
      }

      final versionResult = await _shellRun('node --version');
      if (versionResult.exitCode == 0) {
        final version = _extractVersion(versionResult.stdout.toString());
        if (version == null) {
          return _nodeNotInstalled;
        }
        final pathResult = await _shellRun('which node');
        final installPath = pathResult.exitCode == 0
            ? extractPluginAbsolutePath(pathResult.stdout.toString())
            : null;
        final releaseHint =
            (installPath != null &&
                (installPath.contains('.nvm/') ||
                    installPath.contains('.fnm/')))
            ? 'node'
            : version;
        final latestVersion = await _queryLatestNodeVersion(
          installedVersion: version,
          releaseHint: releaseHint,
        );
        return PluginInfo(
          id: PluginCatalogIds.nodejs,
          name: 'Node.js',
          description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
          status: PluginStatus.installed,
          installedVersion: version,
          latestVersion: _pickHigherNodeVersion(version, latestVersion),
          installPath: installPath?.isEmpty == true ? null : installPath,
          dependents: const <String>[PluginCatalogIds.playwright],
        );
      }
    } catch (e) {
      silentLog('plugin_scanner', '扫描 Node.js', e);
    }
    return _nodeNotInstalled;
  }

  Future<PluginInfo> scanPython() => _runWithFallback(
    operation: '扫描 Python',
    fallback: _pythonNotInstalled,
    operationBody: () async =>
        _pythonInfoFromRuntime(await _resolvePythonRuntime()),
  );

  Future<PluginInfo> _scanPipWithRuntime(_PythonRuntimeScan? runtime) async {
    if (runtime == null) return _pipNotInstalled;
    final pipVersionResult = await runTrackedProcessOrFailed(
      runtime.executable,
      ['-m', 'pip', '--version'],
      timeout: const Duration(seconds: 8),
      tag: 'plugin_scanner.pip_probe',
      environment: pluginProxyEnvironment(),
    );
    if (pipVersionResult.exitCode != 0) {
      return _pipNotInstalled;
    }
    final version = extractPipVersion(
      '${pipVersionResult.stdout}\n${pipVersionResult.stderr}',
    );
    if (version == null) return _pipNotInstalled;
    final latestVersion = switch (runtime.source) {
      _PythonRuntimeSource.pyenv => await _queryLatestPipVersion(),
      _ => null,
    };
    return PluginInfo(
      id: PluginCatalogIds.pip,
      name: 'pip',
      description: 'Python 包管理工具，用于安装、升级与管理 Python 库',
      status: PluginStatus.installed,
      installedVersion: version,
      latestVersion: latestVersion,
      installPath: runtime.executable,
      dependencies: const <String>[PluginCatalogIds.python],
      supportsUninstall: false,
    );
  }

  Future<PluginInfo> scanPip() => _runWithFallback(
    operation: '扫描 pip',
    fallback: _pipNotInstalled,
    operationBody: () async =>
        _scanPipWithRuntime(await _resolvePythonRuntime()),
  );

  Future<PluginInfo> scanPlaywright() async {
    try {
      final installation = await _resolveGlobalNpmPackage('playwright');
      if (installation == null) return _playwrightNotInstalled;
      final versionResult = await _shellRun(
        '${posixShellQuote('node')} '
        '${posixShellQuote(installation.executablePath)} --version',
      );
      if (versionResult.exitCode != 0) return _playwrightNotInstalled;
      final version = versionResult.stdout
          .toString()
          .trim()
          .replaceFirst(_playwrightVersionPrefixPattern, '')
          .trim();
      if (!_semverSearchPattern.hasMatch(version)) {
        return _playwrightNotInstalled;
      }
      final latestVersion = await _queryLatestNpmVersion('playwright');
      final globalRoot = p.dirname(installation.packageDirectory);
      final npmCacheResult = await _shellRun('npm config get cache');
      final npmCache = npmCacheResult.exitCode == 0
          ? extractPluginAbsolutePath(npmCacheResult.stdout.toString())
          : null;
      final dataDirectory = pluginPlaywrightDataDirectory(
        packageDirectory: installation.packageDirectory,
      );
      return PluginInfo(
        id: PluginCatalogIds.playwright,
        name: 'Playwright',
        description: '浏览器自动化测试框架，支持 Chromium / Firefox / WebKit',
        status: PluginStatus.installed,
        installedVersion: version,
        latestVersion: latestVersion,
        installPath: installation.executablePath,
        dependencies: const <String>[PluginCatalogIds.nodejs],
        metadata: <String, Object?>{
          'installation_target': installation.packageDirectory,
          'executable_path': installation.executablePath,
          if (dataDirectory != null) 'data_directory': dataDirectory,
          if (npmCache != null) 'cache_directory': npmCache,
          'npm_global_root': globalRoot,
        },
      );
    } catch (e) {
      silentLog('plugin_scanner', '扫描 Playwright', e);
    }
    return _playwrightNotInstalled;
  }

  Future<PluginInfo> scanHermesAgent() => _runWithFallback(
    operation: '扫描 Hermes Agent',
    fallback: _hermesAgentNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: PluginCatalogIds.hermesAgent,
      name: 'Hermes Agent',
      description: 'Hermes Agent 运行时，用于智能体编排、自我学习与技能沉淀',
      commands: const <String>[hermesAgentCommand, hermesAgentAltCommand],
      versionArgs: const <String>['--version'],
      versionParser: _extractLooseVersion,
      latestNpmPackage: hermesAgentPackageName,
      dependencies: const <String>[PluginCatalogIds.nodejs],
    ),
  );

  Future<String?> _queryDingtalkWorkspaceCliRelease(String url) async {
    final result = Platform.isWindows
        ? await runTrackedProcessOrFailed(
            'powershell.exe',
            <String>[
              '-NoLogo',
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              "(Invoke-RestMethod -Uri '$url').tag_name",
            ],
            timeout: const Duration(seconds: 12),
            tag: 'plugin_scanner.dingtalk_workspace_cli_release',
            environment: pluginProxyEnvironment(),
          )
        : await _runShellScript(
            '${pluginToolchainShellPrefix()}curl -fsSL ${posixShellQuote(url)}',
            tag: 'plugin_scanner.dingtalk_workspace_cli_release',
            timeout: const Duration(seconds: 8),
          );
    if (result.exitCode != 0) return null;
    final output = result.stdout.toString();
    final decoded = _decodeOptionalJson(output);
    final tag = decoded is Map
        ? nullIfBlank('${stringKeyedMapFromValue(decoded)['tag_name'] ?? ''}')
        : null;
    return extractPluginFirstSemver(tag ?? output);
  }

  Future<String?> _queryLatestDingtalkWorkspaceCliVersion() async {
    return _latestDingtalkWorkspaceCliVersionProbe.run(() async {
      return await _queryDingtalkWorkspaceCliRelease(
            'https://api.github.com/repos/DingTalk-Real-AI/dingtalk-workspace-cli/releases/latest',
          ) ??
          await _queryDingtalkWorkspaceCliRelease(
            'https://gitee.com/api/v5/repos/DingTalk-Real-AI/dingtalk-workspace-cli/releases/latest',
          ) ??
          await _queryLatestNpmVersion(pluginDingtalkWorkspaceCliPackage);
    });
  }

  Future<PluginInfo> scanDingtalkWorkspaceCli() => _runWithFallback(
    operation: '扫描 DingTalk Workspace CLI',
    fallback: _dingtalkWorkspaceCliNotInstalled,
    operationBody: () async {
      final executable = await resolvePluginDingtalkWorkspaceCliExecutable(
        tag: 'plugin_scanner.dingtalk_workspace_cli_path',
      );
      if (executable == null || executable.isEmpty) {
        return _dingtalkWorkspaceCliNotInstalled;
      }
      final versionResult = await runTrackedProcessOrFailed(
        executable,
        const <String>['--version'],
        timeout: const Duration(seconds: 8),
        tag: 'plugin_scanner.dingtalk_workspace_cli_version',
        environment: pluginProxyEnvironment(),
      );
      final output = '${versionResult.stdout}\n${versionResult.stderr}'.trim();
      final version = versionResult.exitCode == 0
          ? _extractLooseVersion(output)
          : null;
      final latestVersion = await _queryLatestDingtalkWorkspaceCliVersion();
      final npmInstallation =
          await resolvePluginDingtalkWorkspaceCliNpmPackage();
      final installationTarget =
          npmInstallation?.packageDirectory ?? executable;
      return PluginInfo(
        id: PluginCatalogIds.dingtalkWorkspaceCli,
        name: 'DingTalk Workspace CLI',
        description: '钉钉工作区命令行工具，为 AI Agent 提供钉钉工作流能力',
        status: PluginStatus.installed,
        installedVersion: version,
        latestVersion: latestVersion,
        installPath: executable,
        metadata: <String, Object?>{
          'installation_target': installationTarget,
          'executable_path': executable,
          'installation_method': npmInstallation == null ? '官方脚本' : 'npm',
          'target_os': pluginDingtalkWorkspaceCliTargetOs(),
          'supported_platforms': const <String>[
            'macOS amd64 / arm64',
            'Linux amd64 / arm64',
            'Windows amd64 / arm64',
          ],
          'package_name': pluginDingtalkWorkspaceCliPackage,
          'binary_name': pluginDingtalkWorkspaceCliCommand,
          'repository': pluginDingtalkWorkspaceCliRepository,
          'documentation': pluginDingtalkWorkspaceCliDocumentation,
          'install_command': Platform.isWindows
              ? 'irm ${pluginDingtalkWorkspaceCliInstallScriptUrl()} | iex'
              : 'curl -fsSL ${pluginDingtalkWorkspaceCliInstallScriptUrl()} | sh',
          'upgrade_command': 'dws upgrade -y',
          'uninstall_command': npmInstallation == null
              ? '删除 dws 可执行文件及 ~/.*/skills/dws'
              : 'npm uninstall -g $pluginDingtalkWorkspaceCliPackage',
          if (latestVersion == null)
            'update_check_error': '无法获取 DingTalk Workspace CLI 的最新版本。',
        },
      );
    },
  );

  Future<PluginInfo> scanJava() => _runWithFallback(
    operation: '扫描 Java',
    fallback: _javaNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: PluginCatalogIds.java,
      name: 'Java',
      description: 'JDK 运行时，用于 apktool / jadx 等 Android 静态分析工具',
      commands: const <String>['java'],
      versionArgs: const <String>['-version'],
      versionParser: _extractJavaVersion,
      latestBrewFormula: 'openjdk',
      dependents: const <String>[
        PluginCatalogIds.apktool,
        PluginCatalogIds.jadx,
      ],
    ),
  );

  Future<PluginInfo> scanFrida() => _runWithFallback(
    operation: '扫描 Frida',
    fallback: _fridaNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: PluginCatalogIds.frida,
      name: 'Frida',
      description: '动态插桩与 Hook 工具链，用于 Android 运行时验证',
      commands: const <String>['frida'],
      versionArgs: const <String>['--version'],
      versionParser: _extractLooseVersion,
      latestPypiPackage: 'frida-tools',
      dependencies: const <String>[
        PluginCatalogIds.python,
        PluginCatalogIds.pip,
      ],
    ),
  );

  Future<PluginInfo> scanMitmproxy() => _runWithFallback(
    operation: '扫描 mitmproxy',
    fallback: _mitmproxyNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: PluginCatalogIds.mitmproxy,
      name: 'mitmproxy',
      description: 'HTTP(S) 代理抓包工具，用于 Web / Android 流量取证',
      commands: const <String>['mitmdump', 'mitmproxy'],
      versionArgs: const <String>['--version'],
      versionParser: _extractLooseVersion,
      latestBrewFormula: 'mitmproxy',
    ),
  );

  Future<PluginInfo> scanApktool() => _runWithFallback(
    operation: '扫描 apktool',
    fallback: _apktoolNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: PluginCatalogIds.apktool,
      name: 'apktool',
      description: 'APK 解包与 smali 分析工具',
      commands: const <String>['apktool'],
      versionArgs: const <String>['--version'],
      versionParser: _extractLooseVersion,
      latestBrewFormula: 'apktool',
      dependencies: const <String>[PluginCatalogIds.java],
    ),
  );

  Future<PluginInfo> scanJadx() => _runWithFallback(
    operation: '扫描 jadx',
    fallback: _jadxNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: PluginCatalogIds.jadx,
      name: 'jadx',
      description: 'DEX / APK Java 反编译工具',
      commands: const <String>['jadx'],
      versionArgs: const <String>['--version'],
      versionParser: _extractLooseVersion,
      latestBrewFormula: 'jadx',
      dependencies: const <String>[PluginCatalogIds.java],
    ),
  );

  Future<PluginInfo> scanRadare2() => _runWithFallback(
    operation: '扫描 radare2',
    fallback: _radare2NotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: PluginCatalogIds.radare2,
      name: 'radare2',
      description: '二进制静态分析与 ELF / native so 逆向工具',
      commands: const <String>['r2', 'radare2'],
      versionArgs: const <String>['-v'],
      versionParser: _extractLooseVersion,
      latestBrewFormula: 'radare2',
    ),
  );

  Future<PluginInfo> scanBlutter() => _runWithFallback(
    operation: '扫描 blutter',
    fallback: _blutterNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: PluginCatalogIds.blutter,
      name: 'blutter',
      description: 'Flutter Dart AOT 快速还原工具，用于 libapp.so 分析',
      commands: <String>['blutter', _openHandToolBin('blutter')],
      versionArgs: const <String>['--help'],
      versionParser: (_) => null,
      dependencies: const <String>[
        PluginCatalogIds.python,
        PluginCatalogIds.pip,
      ],
    ),
  );

  Future<PluginInfo> scanDoldrums() => _runWithFallback(
    operation: '扫描 Doldrums',
    fallback: _doldrumsNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: PluginCatalogIds.doldrums,
      name: 'Doldrums',
      description: 'Flutter snapshot / ELF 辅助分析工具',
      commands: <String>['doldrums', 'Doldrums', _openHandToolBin('doldrums')],
      versionArgs: const <String>['--help'],
      versionParser: (_) => null,
      dependencies: const <String>[
        PluginCatalogIds.python,
        PluginCatalogIds.pip,
      ],
    ),
  );

  Future<PluginInfo> scanAnythingAnalyzer() => _runWithFallback(
    operation: '扫描 Anything Analyzer',
    fallback: _anythingAnalyzerNotInstalled,
    operationBody: () async {
      final commandScan = await _scanCommandPlugin(
        id: PluginCatalogIds.anythingAnalyzer,
        name: 'Anything Analyzer',
        description: '协议分析与 MCP Server 工具，用于抓包、分析和 Agent 联动',
        commands: <String>[
          'anything-analyzer',
          _openHandToolBin('anything-analyzer'),
        ],
        versionArgs: const <String>['--version'],
        versionParser: _extractLooseVersion,
      );
      if (commandScan.isInstalled) return commandScan;
      for (final path in _anythingAnalyzerAppCandidates()) {
        if (await probeFileSystemEntityType(path, followLinks: true) !=
            FileSystemEntityType.notFound) {
          return PluginInfo(
            id: PluginCatalogIds.anythingAnalyzer,
            name: 'Anything Analyzer',
            description: '协议分析与 MCP Server 工具，用于抓包、分析和 Agent 联动',
            status: PluginStatus.installed,
            installPath: path,
          );
        }
      }
      return _anythingAnalyzerNotInstalled;
    },
  );

  Future<PluginInfo> scanDocker() async {
    try {
      final pathResult = await _shellRun('command -v docker');
      final desktopAppExists = await pluginDockerDesktopInstallationExists();
      if (pathResult.exitCode != 0) {
        if (desktopAppExists) {
          return const PluginInfo(
            id: PluginCatalogIds.docker,
            name: 'Docker',
            description: '容器运行环境，用于运行 Qdrant 本地向量数据库服务',
            status: PluginStatus.error,
            dependents: <String>[
              PluginCatalogIds.qdrant,
              PluginCatalogIds.postgresql,
              PluginCatalogIds.redis,
            ],
            metadata: <String, Object?>{
              'desktop_app_detected': true,
              'daemon_running': false,
            },
            errorMessage: '检测到 Docker Desktop，但 docker CLI 不在 PATH 中。',
          );
        }
        return _dockerNotInstalled;
      }
      final installPath = extractPluginAbsolutePath(
        pathResult.stdout.toString(),
      );
      final versionResult = await _shellRun('docker --version');
      final version = versionResult.exitCode == 0
          ? _extractLooseVersion(versionResult.stdout.toString())
          : null;
      final contextResult = await _shellRun('docker context show');
      final infoResult = await _shellRun('docker info --format "{{json .}}"');
      final metadata = <String, Object?>{
        'cli_available': true,
        'desktop_app_detected': desktopAppExists,
        'daemon_running': infoResult.exitCode == 0,
        if (contextResult.exitCode == 0)
          'context': contextResult.stdout.toString().trim(),
      };
      if (infoResult.exitCode == 0) {
        final decoded = _decodeOptionalJson(infoResult.stdout.toString());
        if (decoded is Map) {
          final info = stringKeyedMapFromValue(decoded);
          metadata.addAll(<String, Object?>{
            if (info['ServerVersion'] != null)
              'server_version': '${info['ServerVersion']}',
            if (info['OperatingSystem'] != null)
              'docker_os': '${info['OperatingSystem']}',
            if (info['DockerRootDir'] != null)
              'docker_root_dir': '${info['DockerRootDir']}',
            if (info['Name'] != null) 'daemon_name': '${info['Name']}',
            if (info['OSType'] != null) 'os_type': '${info['OSType']}',
            if (info['Architecture'] != null)
              'architecture': '${info['Architecture']}',
          });
        }
        final compose = await _shellRun('docker compose version --short');
        if (compose.exitCode == 0) {
          metadata['compose_version'] = compose.stdout.toString().trim();
        }
        return PluginInfo(
          id: PluginCatalogIds.docker,
          name: 'Docker',
          description: '容器运行环境，用于运行 Qdrant 本地向量数据库服务',
          status: PluginStatus.installed,
          installedVersion: version,
          installPath: installPath,
          dependents: const <String>[
            PluginCatalogIds.qdrant,
            PluginCatalogIds.postgresql,
            PluginCatalogIds.redis,
          ],
          metadata: metadata,
        );
      }
      return PluginInfo(
        id: PluginCatalogIds.docker,
        name: 'Docker',
        description: '容器运行环境，用于运行 Qdrant 本地向量数据库服务',
        status: PluginStatus.error,
        installedVersion: version,
        installPath: installPath,
        dependents: const <String>[
          PluginCatalogIds.qdrant,
          PluginCatalogIds.postgresql,
          PluginCatalogIds.redis,
        ],
        metadata: metadata,
        errorMessage: 'docker CLI 可用，但 Docker daemon 未运行或不可访问。',
      );
    } catch (e, stack) {
      silentLog('plugin_scanner', '扫描 Docker', e, stack);
    }
    return _dockerNotInstalled;
  }

  Future<PluginInfo> scanQdrant() async {
    try {
      final dockerPath = await _shellRun('command -v docker');
      if (dockerPath.exitCode != 0) return _qdrantNotInstalled;
      final dockerInfo = await _shellRun('docker info --format "{{json .}}"');
      if (dockerInfo.exitCode != 0) {
        return _qdrantNotInstalled.copyWith(
          status: PluginStatus.error,
          errorMessage: 'Qdrant 依赖 Docker daemon，请先启动 Docker。',
          metadata: const <String, Object?>{'docker_daemon_running': false},
        );
      }

      final inspectResult = await _shellRun(
        'docker inspect ${posixShellQuote(qdrantContainerName)}',
      );
      if (inspectResult.exitCode != 0) {
        return _qdrantNotInstalled;
      }
      final decoded = _decodeOptionalJson(inspectResult.stdout.toString());
      final metadata = _qdrantInspectMetadataFromDecoded(decoded);
      if (metadata == null) {
        return _qdrantNotInstalled.copyWith(
          status: PluginStatus.error,
          errorMessage: '无法解析 OpenHand Qdrant 容器信息。',
        );
      }
      final image = '${metadata['image'] ?? ''}'.trim();
      final running = metadata['running'] == true;
      final openHandManaged = metadata['openhand_managed'] == true;
      String? qdrantVersion;
      if (running) {
        final health = await _shellRun(
          'curl -fsS http://127.0.0.1:$qdrantRestPort/ 2>/dev/null || true',
        );
        final healthText = health.stdout.toString().trim();
        metadata['health_response'] = healthText;
        final healthJson = _decodeOptionalJson(healthText);
        if (healthJson is Map) {
          qdrantVersion = '${healthJson['version'] ?? ''}'.trim();
          metadata['health_title'] = '${healthJson['title'] ?? ''}'.trim();
        }
        final collections = await _shellRun(
          'curl -fsS http://127.0.0.1:$qdrantRestPort/collections 2>/dev/null || true',
        );
        final collectionsJson = _decodeOptionalJson(
          collections.stdout.toString(),
        );
        if (collectionsJson is Map) {
          final result = collectionsJson['result'];
          if (result is Map && result['collections'] is List) {
            metadata['collection_count'] =
                (result['collections'] as List).length;
          }
        }
      }
      final imageVersion = image.contains(':') ? image.split(':').last : null;
      final installedVersion = qdrantVersion?.isNotEmpty == true
          ? qdrantVersion
          : nullIfBlank('${metadata['image_version'] ?? ''}') ?? imageVersion;
      if (!openHandManaged) {
        return PluginInfo(
          id: PluginCatalogIds.qdrant,
          name: 'Qdrant',
          description: '本地向量数据库，用于知识库 embedding 向量索引与检索',
          status: PluginStatus.error,
          installedVersion: installedVersion,
          dependencies: const <String>[PluginCatalogIds.docker],
          metadata: metadata,
          errorMessage: '检测到同名 Qdrant 容器，但缺少 OpenHand 管理标记。',
        );
      }
      final imageUpdate = await _scanContainerImageUpdate(metadata: metadata);
      metadata.addAll(imageUpdate.metadata);
      return PluginInfo(
        id: PluginCatalogIds.qdrant,
        name: 'Qdrant',
        description: '本地向量数据库，用于知识库 embedding 向量索引与检索',
        status: PluginStatus.installed,
        enabled: running,
        installedVersion: installedVersion ?? imageUpdate.installedVersion,
        latestVersion: imageUpdate.latestVersion,
        updateAvailable: imageUpdate.updateAvailable,
        installPath: '${metadata['data_directory'] ?? ''}'.trim().isEmpty
            ? null
            : '${metadata['data_directory']}',
        dependencies: const <String>[PluginCatalogIds.docker],
        metadata: metadata,
      );
    } catch (e, stack) {
      silentLog('plugin_scanner', '扫描 Qdrant', e, stack);
    }
    return _qdrantNotInstalled;
  }

  Future<PluginInfo> scanPostgresql() async {
    return _scanManagedDatabase(
      id: PluginCatalogIds.postgresql,
      name: 'PostgreSQL',
      description: '关系型数据库服务，供 AI 暴露面扫描保存任务与审计数据',
      containerName: ManagedServiceDefaults.postgresqlContainerName,
      endpoint: ManagedServiceDefaults.postgresqlEndpoint,
      dataDestination: ManagedServiceDefaults.postgresqlDataDestination,
      cliCommand: 'psql',
      versionCommand: 'psql --version',
      versionEnvironmentKey: 'PG_VERSION',
      readinessCommand:
          'pg_isready -h 127.0.0.1 -p ${ManagedServiceDefaults.postgresqlPort} 2>/dev/null',
      fallback: _postgresqlNotInstalled,
    );
  }

  Future<PluginInfo> scanRedis() async {
    return _scanManagedDatabase(
      id: PluginCatalogIds.redis,
      name: 'Redis',
      description: '内存数据存储服务，供 AI 暴露面扫描执行缓存与任务队列',
      containerName: ManagedServiceDefaults.redisContainerName,
      endpoint: ManagedServiceDefaults.redisEndpoint,
      dataDestination: ManagedServiceDefaults.redisDataDestination,
      cliCommand: 'redis-cli',
      versionCommand: 'redis-cli --version',
      versionEnvironmentKey: 'REDIS_VERSION',
      readinessCommand:
          'redis-cli -h 127.0.0.1 -p ${ManagedServiceDefaults.redisPort} ping 2>/dev/null',
      expectedReadinessOutput: 'PONG',
      fallback: _redisNotInstalled,
    );
  }

  Future<PluginInfo> _scanManagedDatabase({
    required String id,
    required String name,
    required String description,
    required String containerName,
    required String endpoint,
    required String dataDestination,
    required String cliCommand,
    required String versionCommand,
    required String versionEnvironmentKey,
    required String readinessCommand,
    required PluginInfo fallback,
    String? expectedReadinessOutput,
  }) async {
    try {
      final dockerPath = await _shellRun('command -v docker');
      final dockerAvailable = dockerPath.exitCode == 0;
      var dockerDaemonRunning = false;
      if (dockerAvailable) {
        final dockerInfo = await _shellRun('docker info --format "{{json .}}"');
        dockerDaemonRunning = dockerInfo.exitCode == 0;
        if (dockerDaemonRunning) {
          final inspect = await _shellRun(
            'docker inspect ${posixShellQuote(containerName)}',
          );
          if (inspect.exitCode == 0) {
            final metadata = _managedDatabaseMetadataFromDecoded(
              _decodeOptionalJson(inspect.stdout.toString()),
              containerName: containerName,
              endpoint: endpoint,
              dataDestination: dataDestination,
              versionEnvironmentKey: versionEnvironmentKey,
            );
            if (metadata == null) {
              return fallback.copyWith(
                status: PluginStatus.error,
                errorMessage: '无法解析 $name 容器信息。',
              );
            }
            final image = '${metadata['image'] ?? ''}'.trim();
            var installedVersion = image.contains(':')
                ? image.split(':').last
                : null;
            if (metadata['openhand_managed'] != true) {
              return PluginInfo(
                id: id,
                name: name,
                description: description,
                status: PluginStatus.error,
                installedVersion: installedVersion,
                supportsUninstall: false,
                supportsInstall: false,
                metadata: <String, Object?>{
                  ...metadata,
                  'runtime_managed': false,
                  'external_service': true,
                },
                errorMessage: '检测到同名 $name 容器，但缺少 OpenHand 管理标记。',
              );
            }
            final imageUpdate = await _scanContainerImageUpdate(
              metadata: metadata,
              versionEnvironmentKey: versionEnvironmentKey,
            );
            metadata.addAll(imageUpdate.metadata);
            installedVersion = imageUpdate.installedVersion ?? installedVersion;
            final running = metadata['running'] == true;
            final dataDirectory = '${metadata['data_directory'] ?? ''}'.trim();
            return PluginInfo(
              id: id,
              name: name,
              description: description,
              status: PluginStatus.installed,
              enabled: running,
              installedVersion: installedVersion,
              latestVersion: imageUpdate.latestVersion,
              updateAvailable: imageUpdate.updateAvailable,
              installPath: dataDirectory.isEmpty ? null : dataDirectory,
              dependencies: const <String>[PluginCatalogIds.docker],
              metadata: metadata,
            );
          }
        }
      }

      final cli = await _shellRun('command -v $cliCommand');
      final ready = await _shellRun(readinessCommand);
      final cliAvailable = cli.exitCode == 0;
      final serviceRunning =
          ready.exitCode == 0 &&
          (expectedReadinessOutput == null ||
              ready.stdout.toString().trim().toUpperCase() ==
                  expectedReadinessOutput.toUpperCase());
      final versionResult = cliAvailable
          ? await _shellRun(versionCommand)
          : null;
      final version = versionResult == null || versionResult.exitCode != 0
          ? null
          : _extractLooseVersion(versionResult.stdout.toString());
      if (!serviceRunning) {
        return fallback.copyWith(
          installedVersion: version,
          installPath: cliAvailable
              ? extractPluginAbsolutePath(cli.stdout.toString())
              : null,
          metadata: <String, Object?>{
            ...fallback.metadata,
            'runtime_managed': true,
            'docker_daemon_running': dockerDaemonRunning,
            'cli_available': cliAvailable,
            'service_running': false,
          },
        );
      }
      return PluginInfo(
        id: id,
        name: name,
        description: description,
        status: PluginStatus.error,
        installedVersion: version,
        installPath: cliAvailable
            ? extractPluginAbsolutePath(cli.stdout.toString())
            : null,
        supportsUninstall: false,
        supportsInstall: false,
        metadata: <String, Object?>{
          'external_service': true,
          'runtime_managed': false,
          'docker_daemon_running': dockerDaemonRunning,
          'cli_available': cliAvailable,
          'service_running': true,
          'endpoint': endpoint,
        },
        errorMessage: '检测到外部 $name 服务，OpenHand 不会接管或卸载该实例。',
      );
    } catch (error, stack) {
      silentLog('plugin_scanner', '扫描 $name', error, stack);
    }
    return fallback;
  }

  static String _formatDockerPorts(Object? value) {
    if (value is! Map) return '';
    final parts = <String>[];
    for (final entry in value.entries) {
      final bindings = entry.value;
      if (bindings is List && bindings.isNotEmpty) {
        for (final binding in bindings) {
          if (binding is Map) {
            final bindingMap = stringKeyedMapFromValue(binding);
            final hostIp = '${bindingMap['HostIp'] ?? ''}'.trim();
            final hostPort = '${bindingMap['HostPort'] ?? ''}'.trim();
            if (hostIp.isEmpty && hostPort.isEmpty) continue;
            parts.add('${entry.key} -> $hostIp:$hostPort');
          }
        }
      }
    }
    return parts.join(', ');
  }

  static String _formatRestartPolicy(Object? value) {
    final map = stringKeyedMapFromValue(value);
    if (map.isEmpty) return '';
    final name = '${map['Name'] ?? ''}'.trim();
    final maximumRetryCount = '${map['MaximumRetryCount'] ?? ''}'.trim();
    if (maximumRetryCount.isEmpty || maximumRetryCount == '0') return name;
    return '$name ($maximumRetryCount)';
  }

  static String _extractHostDataDirectory(
    Object? mounts, {
    String destination = _qdrantStorageDestination,
  }) {
    if (mounts is! List) return '';
    for (final mount in mounts) {
      if (mount is! Map) continue;
      final mountMap = stringKeyedMapFromValue(mount);
      final mountDestination = '${mountMap['Destination'] ?? ''}'.trim();
      if (mountDestination == destination) {
        return '${mountMap['Source'] ?? ''}'.trim();
      }
    }
    return '';
  }

  static String _openHandToolBin(String name) {
    return p.join(
      OpenHandPaths.defaultAndroidReverseToolsDirectoryPath(),
      'bin',
      name,
    );
  }

  static List<String> _anythingAnalyzerAppCandidates() {
    final toolRoot = OpenHandPaths.defaultAndroidReverseToolsDirectoryPath();
    return <String>[
      '/Applications/Anything Analyzer.app',
      p.join(
        OpenHandPaths.homeDirectoryPath(),
        'Applications',
        'Anything Analyzer.app',
      ),
      p.join(toolRoot, 'anything-analyzer', 'current', 'Anything Analyzer.app'),
      p.join(toolRoot, 'anything-analyzer', 'Anything Analyzer.app'),
    ];
  }

  static const _nodeNotInstalled = PluginInfo(
    id: PluginCatalogIds.nodejs,
    name: 'Node.js',
    description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
    status: PluginStatus.notInstalled,
    dependents: [PluginCatalogIds.playwright, PluginCatalogIds.hermesAgent],
  );

  static const _playwrightNotInstalled = PluginInfo(
    id: PluginCatalogIds.playwright,
    name: 'Playwright',
    description: '浏览器自动化测试框架，支持 Chromium / Firefox / WebKit',
    status: PluginStatus.notInstalled,
    dependencies: <String>[PluginCatalogIds.nodejs],
  );

  static const _hermesAgentNotInstalled = PluginInfo(
    id: PluginCatalogIds.hermesAgent,
    name: 'Hermes Agent',
    description: 'Hermes Agent 运行时，用于智能体编排、自我学习与技能沉淀',
    status: PluginStatus.notInstalled,
    dependencies: [PluginCatalogIds.nodejs],
  );

  static const _dingtalkWorkspaceCliNotInstalled = PluginInfo(
    id: PluginCatalogIds.dingtalkWorkspaceCli,
    name: 'DingTalk Workspace CLI',
    description: '钉钉工作区命令行工具，为 AI Agent 提供钉钉工作流能力',
    status: PluginStatus.notInstalled,
    metadata: <String, Object?>{
      'target_os': '按当前操作系统选择官方安装脚本',
      'supported_platforms': <String>[
        'macOS amd64 / arm64',
        'Linux amd64 / arm64',
        'Windows amd64 / arm64',
      ],
      'package_name': pluginDingtalkWorkspaceCliPackage,
      'binary_name': pluginDingtalkWorkspaceCliCommand,
      'repository': pluginDingtalkWorkspaceCliRepository,
      'documentation': pluginDingtalkWorkspaceCliDocumentation,
      'install_command': '按当前系统选择 install.sh / install.ps1',
      'upgrade_command': 'dws upgrade -y',
      'uninstall_command': '删除 dws 可执行文件及技能目录',
    },
  );

  static const _pythonNotInstalled = PluginInfo(
    id: PluginCatalogIds.python,
    name: 'Python',
    description: 'Python 运行时环境，用于执行 Python 脚本、库与扩展能力',
    status: PluginStatus.notInstalled,
  );

  static const _pipNotInstalled = PluginInfo(
    id: PluginCatalogIds.pip,
    name: 'pip',
    description: 'Python 包管理工具，用于安装、升级与管理 Python 库',
    status: PluginStatus.notInstalled,
    dependencies: <String>[PluginCatalogIds.python],
    supportsUninstall: false,
  );

  static const _javaNotInstalled = PluginInfo(
    id: PluginCatalogIds.java,
    name: 'Java',
    description: 'JDK 运行时，用于 apktool / jadx 等 Android 静态分析工具',
    status: PluginStatus.notInstalled,
    dependents: <String>[PluginCatalogIds.apktool, PluginCatalogIds.jadx],
  );

  static const _fridaNotInstalled = PluginInfo(
    id: PluginCatalogIds.frida,
    name: 'Frida',
    description: '动态插桩与 Hook 工具链，用于 Android 运行时验证',
    status: PluginStatus.notInstalled,
    dependencies: <String>[PluginCatalogIds.python, PluginCatalogIds.pip],
  );

  static const _mitmproxyNotInstalled = PluginInfo(
    id: PluginCatalogIds.mitmproxy,
    name: 'mitmproxy',
    description: 'HTTP(S) 代理抓包工具，用于 Web / Android 流量取证',
    status: PluginStatus.notInstalled,
  );

  static const _apktoolNotInstalled = PluginInfo(
    id: PluginCatalogIds.apktool,
    name: 'apktool',
    description: 'APK 解包与 smali 分析工具',
    status: PluginStatus.notInstalled,
    dependencies: <String>[PluginCatalogIds.java],
  );

  static const _jadxNotInstalled = PluginInfo(
    id: PluginCatalogIds.jadx,
    name: 'jadx',
    description: 'DEX / APK Java 反编译工具',
    status: PluginStatus.notInstalled,
    dependencies: <String>[PluginCatalogIds.java],
  );

  static const _radare2NotInstalled = PluginInfo(
    id: PluginCatalogIds.radare2,
    name: 'radare2',
    description: '二进制静态分析与 ELF / native so 逆向工具',
    status: PluginStatus.notInstalled,
  );

  static const _blutterNotInstalled = PluginInfo(
    id: PluginCatalogIds.blutter,
    name: 'blutter',
    description: 'Flutter Dart AOT 快速还原工具，用于 libapp.so 分析',
    status: PluginStatus.notInstalled,
    dependencies: <String>[PluginCatalogIds.python, PluginCatalogIds.pip],
  );

  static const _doldrumsNotInstalled = PluginInfo(
    id: PluginCatalogIds.doldrums,
    name: 'Doldrums',
    description: 'Flutter snapshot / ELF 辅助分析工具',
    status: PluginStatus.notInstalled,
    dependencies: <String>[PluginCatalogIds.python, PluginCatalogIds.pip],
  );

  static const _anythingAnalyzerNotInstalled = PluginInfo(
    id: PluginCatalogIds.anythingAnalyzer,
    name: 'Anything Analyzer',
    description: '协议分析与 MCP Server 工具，用于抓包、分析和 Agent 联动',
    status: PluginStatus.notInstalled,
  );

  static const _dockerNotInstalled = PluginInfo(
    id: PluginCatalogIds.docker,
    name: 'Docker',
    description: '容器运行环境，用于运行 Qdrant 本地向量数据库服务',
    status: PluginStatus.notInstalled,
    dependents: <String>[
      PluginCatalogIds.qdrant,
      PluginCatalogIds.postgresql,
      PluginCatalogIds.redis,
    ],
  );

  static const _qdrantNotInstalled = PluginInfo(
    id: PluginCatalogIds.qdrant,
    name: 'Qdrant',
    description: '本地向量数据库，用于知识库 embedding 向量索引与检索',
    status: PluginStatus.notInstalled,
    dependencies: <String>[PluginCatalogIds.docker],
  );

  static const _postgresqlNotInstalled = PluginInfo(
    id: PluginCatalogIds.postgresql,
    name: 'PostgreSQL',
    description: '关系型数据库服务，供 AI 暴露面扫描保存任务与审计数据',
    status: PluginStatus.notInstalled,
    dependencies: <String>[PluginCatalogIds.docker],
    metadata: <String, Object?>{
      'runtime_managed': true,
      'endpoint': ManagedServiceDefaults.postgresqlEndpoint,
      'container_name': ManagedServiceDefaults.postgresqlContainerName,
      'image': ManagedServiceDefaults.postgresqlImage,
      'ports': '127.0.0.1:${ManagedServiceDefaults.postgresqlPort}',
    },
  );

  static const _redisNotInstalled = PluginInfo(
    id: PluginCatalogIds.redis,
    name: 'Redis',
    description: '内存数据存储服务，供 AI 暴露面扫描执行缓存与任务队列',
    status: PluginStatus.notInstalled,
    dependencies: <String>[PluginCatalogIds.docker],
    metadata: <String, Object?>{
      'runtime_managed': true,
      'endpoint': ManagedServiceDefaults.redisEndpoint,
      'container_name': ManagedServiceDefaults.redisContainerName,
      'image': ManagedServiceDefaults.redisImage,
      'ports': '127.0.0.1:${ManagedServiceDefaults.redisPort}',
    },
  );

  static const _aiJunglerPlugin = PluginInfo(
    id: PluginCatalogIds.aiJungler,
    name: 'AI Jungler Engine',
    description: 'OpenHand 自研 AI 基础设施暴露面发现、凭证识别与授权验证引擎',
    status: PluginStatus.installed,
    installedVersion: '0.1.0',
    installPath: 'assets/ai_jungler',
    supportsUninstall: false,
    metadata: <String, Object?>{
      'bundled': true,
      'runtime': 'Rust',
      'service': 'AI 基础设施暴露面扫描',
      'sources': <String>['GitHub', 'Gitee', 'GitCode', 'FOFA', 'Shodan'],
    },
  );

  static List<PluginInfo> knownPluginPlaceholders() => const <PluginInfo>[
    _nodeNotInstalled,
    _playwrightNotInstalled,
    _pythonNotInstalled,
    _pipNotInstalled,
    _javaNotInstalled,
    _fridaNotInstalled,
    _mitmproxyNotInstalled,
    _apktoolNotInstalled,
    _jadxNotInstalled,
    _radare2NotInstalled,
    _blutterNotInstalled,
    _doldrumsNotInstalled,
    _anythingAnalyzerNotInstalled,
    _dockerNotInstalled,
    _qdrantNotInstalled,
    _postgresqlNotInstalled,
    _redisNotInstalled,
    _hermesAgentNotInstalled,
    _aiJunglerPlugin,
    _dingtalkWorkspaceCliNotInstalled,
  ];

  Future<List<PluginInfo>> scanAll() async {
    final scanGate = OpenHandAsyncSemaphore(_maxConcurrentScans);
    Future<T> runScan<T>(Future<T> Function() scan) {
      return scanGate.withPermit(scan);
    }

    final nodeFuture = runScan(scanNodeJs);
    final playwrightFuture = runScan(scanPlaywright);
    final hermesAgentFuture = runScan(scanHermesAgent);
    final dingtalkWorkspaceCliFuture = runScan(scanDingtalkWorkspaceCli);
    final javaFuture = runScan(scanJava);
    final fridaFuture = runScan(scanFrida);
    final mitmproxyFuture = runScan(scanMitmproxy);
    final apktoolFuture = runScan(scanApktool);
    final jadxFuture = runScan(scanJadx);
    final radare2Future = runScan(scanRadare2);
    final blutterFuture = runScan(scanBlutter);
    final doldrumsFuture = runScan(scanDoldrums);
    final anythingAnalyzerFuture = runScan(scanAnythingAnalyzer);
    final dockerFuture = runScan(scanDocker);
    final postgresqlFuture = runScan(scanPostgresql);
    final redisFuture = runScan(scanRedis);
    final pythonRuntimeFuture = runScan(_resolvePythonRuntime);
    final nodeJs = await nodeFuture;
    final playwright = await playwrightFuture;
    final hermesAgent = await hermesAgentFuture;
    final dingtalkWorkspaceCli = await dingtalkWorkspaceCliFuture;
    final java = await javaFuture;
    final frida = await fridaFuture;
    final mitmproxy = await mitmproxyFuture;
    final apktool = await apktoolFuture;
    final jadx = await jadxFuture;
    final radare2 = await radare2Future;
    final blutter = await blutterFuture;
    final doldrums = await doldrumsFuture;
    final anythingAnalyzer = await anythingAnalyzerFuture;
    final docker = await dockerFuture;
    final qdrant = await scanQdrant();
    final postgresql = await postgresqlFuture;
    final redis = await redisFuture;
    final pythonRuntime = await _runWithFallback<_PythonRuntimeScan?>(
      operation: '解析 Python 运行时',
      fallback: null,
      operationBody: () => pythonRuntimeFuture,
    );
    final python = _pythonInfoFromRuntime(pythonRuntime);
    final pip = await _runWithFallback(
      operation: '扫描 pip',
      fallback: _pipNotInstalled,
      operationBody: () => _scanPipWithRuntime(pythonRuntime),
    );
    final updatedNodeJs = nodeJs.copyWith(
      dependents: <String>[
        if (playwright.isInstalled) PluginCatalogIds.playwright,
        if (hermesAgent.isInstalled) PluginCatalogIds.hermesAgent,
      ],
    );
    final updatedDocker = docker.copyWith(
      dependents: <String>[
        if (qdrant.isInstalled) PluginCatalogIds.qdrant,
        if (postgresql.isInstalled) PluginCatalogIds.postgresql,
        if (redis.isInstalled) PluginCatalogIds.redis,
      ],
    );
    final updatedJava = java.copyWith(
      dependents: <String>[
        if (apktool.isInstalled) PluginCatalogIds.apktool,
        if (jadx.isInstalled) PluginCatalogIds.jadx,
      ],
    );
    return [
      updatedNodeJs,
      playwright,
      python,
      pip,
      updatedJava,
      frida,
      mitmproxy,
      apktool,
      jadx,
      radare2,
      blutter,
      doldrums,
      anythingAnalyzer,
      updatedDocker,
      qdrant,
      postgresql,
      redis,
      hermesAgent,
      _aiJunglerPlugin,
      dingtalkWorkspaceCli,
    ];
  }
}

enum _PythonRuntimeSource { pyenv, homebrew, system, unknown }

class _ContainerImageUpdateState {
  const _ContainerImageUpdateState({
    required this.installedVersion,
    required this.metadata,
    this.latestVersion,
    this.updateAvailable,
  });

  final String? installedVersion;
  final String? latestVersion;
  final bool? updateAvailable;
  final Map<String, Object?> metadata;
}

class _PythonRuntimeScan {
  const _PythonRuntimeScan({
    required this.version,
    required this.executable,
    required this.latestVersion,
    required this.source,
    this.pyenvVersion,
    this.brewFormula,
  });

  final String version;
  final String executable;
  final String? latestVersion;
  final _PythonRuntimeSource source;
  final String? pyenvVersion;
  final String? brewFormula;
}
