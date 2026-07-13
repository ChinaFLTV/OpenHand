import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/version_compare.dart';
import '../model/plugin_info.dart';
import 'plugin_toolchain_shell.dart';

Map<String, Object?>? _qdrantInspectMetadataFromDecoded(Object? decoded) {
  if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
    return null;
  }

  final inspect = stringKeyedMapFromValue(decoded.first);
  final state = stringKeyedMapFromValue(inspect['State']);
  final config = stringKeyedMapFromValue(inspect['Config']);
  final networkSettings = stringKeyedMapFromValue(inspect['NetworkSettings']);
  final hostConfig = stringKeyedMapFromValue(inspect['HostConfig']);
  final labels = stringKeyedMapFromValue(config['Labels']);
  final openHandManaged =
      boolFromValue(labels['openhand.managed']) ||
      boolFromValue(labels['com.openhand.managed']);
  final image = '${config['Image'] ?? ''}'.trim();

  return <String, Object?>{
    'docker_daemon_running': true,
    'openhand_managed': openHandManaged,
    'container_id': '${inspect['Id'] ?? ''}'.trim(),
    'container_name': PluginScannerService.qdrantContainerName,
    'container_status': '${state['Status'] ?? ''}'.trim(),
    'running': boolFromValue(state['Running']),
    'started_at': '${state['StartedAt'] ?? ''}'.trim(),
    'finished_at': '${state['FinishedAt'] ?? ''}'.trim(),
    'restart_count': optionalNonNegativeIntFromValue(state['RestartCount']),
    'exit_code': optionalNonNegativeIntFromValue(state['ExitCode']),
    'image': image,
    'image_id': '${inspect['Image'] ?? ''}'.trim(),
    'ports': PluginScannerService._formatDockerPorts(networkSettings['Ports']),
    'restart_policy': PluginScannerService._formatRestartPolicy(
      hostConfig['RestartPolicy'],
    ),
    'rest_endpoint': 'http://127.0.0.1:${PluginScannerService.qdrantRestPort}',
    'grpc_endpoint': '127.0.0.1:${PluginScannerService.qdrantGrpcPort}',
    'data_directory': PluginScannerService._extractHostDataDirectory(
      inspect['Mounts'],
    ),
  };
}

/// 扫描本机已安装的插件（NodeJS / Playwright / Python / pip），检测版本与可用性。
///
/// 对于 nvm / pyenv 用户，优先直接解析或借助管理器拿到真实可执行路径，
/// 避免 GUI 应用进程 PATH 与终端不一致的问题。
class PluginScannerService {
  PluginScannerService();

  static const String hermesAgentPackageName = 'hermes-agent';
  static const String hermesAgentCommand = 'hermes-agent';
  static const String hermesAgentAltCommand = 'hermes';
  static const String qdrantContainerName = 'openhand-qdrant';
  static const String qdrantImageName = 'qdrant/qdrant';
  static const String qdrantDefaultTag = 'latest';
  static const int qdrantRestPort = 6333;
  static const int qdrantGrpcPort = 6334;
  static final RegExp _nvmMajorAliasPattern = RegExp(r'^v?\d+$');
  static final RegExp _nvmFullVersionAliasPattern = RegExp(
    r'^v?\d+\.\d+\.\d+$',
  );
  static final RegExp _nodeVersionOutputPattern = RegExp(r'v(\d+\.\d+\.\d+)');
  static final RegExp _nodeMajorVersionPattern = RegExp(r'v?(\d+)');
  static final RegExp _strictNodeVersionPattern = RegExp(r'^v\d+\.\d+\.\d+$');
  static final RegExp _pyenvVersionPathPattern = RegExp(
    r'/.pyenv/versions/([^/]+)/',
  );
  static final RegExp _brewPythonFormulaPathPattern = RegExp(
    r'/(python(?:@[\d.]+)?)(?:/|$)',
  );
  static final RegExp _semverSearchPattern = RegExp(r'(\d+\.\d+\.\d+)');
  static final RegExp _shellWhitespacePattern = RegExp(r'\s+');
  static final RegExp _playwrightVersionPrefixPattern = RegExp(
    r'^Version\s+',
    caseSensitive: false,
  );
  static final RegExp _stablePyenvVersionLinePattern = RegExp(
    r'^\s*(\d+\.\d+\.\d+)\s*$',
  );
  static final RegExp _looseVersionPattern = RegExp(
    r'(\d+(?:\.\d+)+(?:[-+._A-Za-z0-9]*)?)',
  );
  static final RegExp _quotedJavaVersionPattern = RegExp(
    r'version\s+"([^"]+)"',
  );

  Future<_PythonRuntimeScan?>? _pythonRuntimeProbe;
  final Map<String, Future<String?>> _brewLatestVersionProbes =
      <String, Future<String?>>{};
  Future<String?>? _latestPipVersionProbe;

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

  static String _pickShell() {
    final shell = Platform.environment['SHELL'];
    if (shell != null && shell.isNotEmpty) return shell;
    return '/bin/zsh';
  }

  /// 把 SystemProxyResolver 解析出的代理端点叠加到子进程环境。
  /// 几乎所有 scanner 路径都可能触网（curl nodejs.org / PyPI / npm view
  /// / brew info / pyenv install --list / ghcr.io 等），所以统一加
  /// 代理；本地查 --version / which / command -v 时也带上，对本地命令
  /// 是 no-op，对网络命令是必备通道。
  static Map<String, String> _proxyEnv() {
    return SystemProxyResolver.instance.resolveSubprocessEnvironment();
  }

  Future<ProcessResult> _runShellScript(
    String script, {
    String tag = 'plugin_scanner.shell_probe',
  }) {
    return runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', script],
      timeout: const Duration(seconds: 15),
      tag: tag,
      environment: _proxyEnv(),
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

  String _readNvmDefaultAlias() {
    final home = Platform.environment['HOME'] ?? '';
    final nvmDir = Platform.environment['NVM_DIR'] ?? '$home/.nvm';
    try {
      final aliasFile = File('$nvmDir/alias/default');
      if (aliasFile.existsSync()) {
        final alias = aliasFile.readAsStringSync().trim();
        if (alias.isNotEmpty) return alias;
      }
    } catch (error, stack) {
      silentLog('plugin_scanner', 'read nvm default alias', error, stack);
    }
    return 'node';
  }

  /// 直接从 nvm 目录结构解析当前默认 Node 版本（不依赖 shell）。
  Future<({String version, String nodeBin, String npmBin})?>
  _resolveNvmDirect() async {
    final home = Platform.environment['HOME'] ?? '';
    final nvmDir = Platform.environment['NVM_DIR'] ?? '$home/.nvm';
    final versionsDir = Directory('$nvmDir/versions/node');
    if (!versionsDir.existsSync()) return null;

    final versions = <String>[];
    try {
      await for (final entity in versionsDir.list()) {
        if (entity is Directory) {
          final name = entity.path.split('/').last;
          if (name.startsWith('v')) versions.add(name);
        }
      }
    } catch (error, stack) {
      silentLog('plugin_scanner', 'list nvm versions', error, stack);
      return null;
    }
    if (versions.isEmpty) return null;
    versions.sort(compareSemanticVersions);

    final alias = _readNvmDefaultAlias();

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

    final nodeBin = '$nvmDir/versions/node/$resolvedVersion/bin/node';
    final npmBin = '$nvmDir/versions/node/$resolvedVersion/bin/npm';
    if (!File(nodeBin).existsSync()) return null;
    return (version: resolvedVersion, nodeBin: nodeBin, npmBin: npmBin);
  }

  static String? _extractAbsolutePath(String output) {
    for (final line in output.split('\n').reversed) {
      final trimmed = line.trim();
      if (trimmed.startsWith('/')) return trimmed;
    }
    return null;
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
    final match = _nodeMajorVersionPattern.firstMatch(version);
    return optionalNonNegativeIntFromValue(match?.group(1));
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

  static bool _looksLikeHomebrewPath(String path) {
    return path.contains('/Cellar/python') ||
        path.contains('/Homebrew/Cellar/python') ||
        path.contains('/opt/homebrew/') ||
        path.contains('/usr/local/opt/python') ||
        path.contains('/usr/local/bin/python');
  }

  static bool _looksLikeSystemPython(String path) {
    return path.startsWith('/usr/bin/') ||
        path.startsWith('/Library/Developer/CommandLineTools/');
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
    final home = Platform.environment['HOME'] ?? '';
    if (File('$home/.pyenv/bin/pyenv').existsSync()) return true;
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
    final quickVersion = _extractFirstSemver(
      '${quickResult.stdout}\n${quickResult.stderr}',
      prefix: '$majorMinor.',
    );
    if (quickVersion != null) return quickVersion;

    final listResult = await _shellRun('pyenv install --list');
    if (listResult.exitCode != 0) return null;
    final versions = _extractStablePyenvVersions(
      listResult.stdout.toString(),
      prefix: '$majorMinor.',
    );
    if (versions.isEmpty) return null;
    versions.sort(compareSemanticVersions);
    return versions.last;
  }

  Future<String?> _queryBrewLatestVersion(String formula) async {
    final normalizedFormula = formula.trim();
    if (normalizedFormula.isEmpty) return null;
    final active = _brewLatestVersionProbes[normalizedFormula];
    if (active != null) return active;
    late final Future<String?> probe;
    probe = _queryBrewLatestVersionUncached(normalizedFormula).whenComplete(() {
      if (identical(_brewLatestVersionProbes[normalizedFormula], probe)) {
        _brewLatestVersionProbes.remove(normalizedFormula);
      }
    });
    _brewLatestVersionProbes[normalizedFormula] = probe;
    return probe;
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

  Future<String?> _queryLatestPipVersion() async {
    final active = _latestPipVersionProbe;
    if (active != null) return active;
    late final Future<String?> probe;
    probe = _queryLatestPipVersionUncached().whenComplete(() {
      if (identical(_latestPipVersionProbe, probe)) {
        _latestPipVersionProbe = null;
      }
    });
    _latestPipVersionProbe = probe;
    return probe;
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
    final version = _extractFirstSemver(result.stdout.toString());
    return version;
  }

  static String? _extractFirstSemver(String output, {String? prefix}) {
    final matches = _semverSearchPattern.allMatches(output);
    for (final match in matches) {
      final value = match.group(1);
      if (value == null) continue;
      if (prefix == null || value.startsWith(prefix)) return value;
    }
    return null;
  }

  static List<String> _extractStablePyenvVersions(
    String output, {
    String? prefix,
  }) {
    final versions = <String>{};
    for (final match in _stablePyenvVersionLinePattern.allMatches(output)) {
      final value = match.group(1);
      if (value == null) continue;
      if (prefix != null && !value.startsWith(prefix)) continue;
      versions.add(value);
    }
    return versions.toList(growable: false);
  }

  static String? _extractLooseVersion(String output) {
    final match = _looseVersionPattern.firstMatch(output);
    return match?.group(1);
  }

  static String _shellQuote(String value) {
    return pluginToolchainShellQuote(value);
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
      final installPath = _extractAbsolutePath(pathResult.stdout.toString());
      if (installPath == null || installPath.isEmpty) continue;
      final versionResult = await _shellRun(
        [_shellQuote(installPath), ...versionArgs.map(_shellQuote)].join(' '),
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
      'nodejs' => _nodeNotInstalled,
      'playwright' => _playwrightNotInstalled,
      PluginCatalogIds.hermesAgent => _hermesAgentNotInstalled,
      'python' => _pythonNotInstalled,
      'pip' => _pipNotInstalled,
      'java' => _javaNotInstalled,
      'frida' => _fridaNotInstalled,
      'mitmproxy' => _mitmproxyNotInstalled,
      'apktool' => _apktoolNotInstalled,
      'jadx' => _jadxNotInstalled,
      'radare2' => _radare2NotInstalled,
      'blutter' => _blutterNotInstalled,
      'doldrums' => _doldrumsNotInstalled,
      'anything_analyzer' => _anythingAnalyzerNotInstalled,
      'docker' => _dockerNotInstalled,
      'qdrant' => _qdrantNotInstalled,
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
              .split(_shellWhitespacePattern)
              .first
        : null;
    for (final command in const ['python3', 'python']) {
      final whichResult = await _shellRun('pyenv which $command');
      if (whichResult.exitCode != 0) continue;
      final executable = _extractAbsolutePath(whichResult.stdout.toString());
      if (executable == null || executable.isEmpty) continue;
      final versionResult = await runTrackedProcessOrFailed(
        executable,
        ['--version'],
        timeout: const Duration(seconds: 5),
        tag: 'plugin_scanner.python_probe',
        environment: _proxyEnv(),
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
      final formula = _looksLikeHomebrewPath(executable)
          ? (_extractBrewPythonFormulaFromPath(executable) ?? 'python')
          : null;
      final source = managedPyenvVersion != null
          ? _PythonRuntimeSource.pyenv
          : formula != null
          ? _PythonRuntimeSource.homebrew
          : _looksLikeSystemPython(executable)
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
          ? _extractAbsolutePath(pathResult.stdout.toString())
          : null;
      if (executable == null || executable.isEmpty) continue;
      final formula = _looksLikeHomebrewPath(executable)
          ? (_extractBrewPythonFormulaFromPath(executable) ?? 'python')
          : null;
      final source = formula != null
          ? _PythonRuntimeSource.homebrew
          : _looksLikeSystemPython(executable)
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
    final active = _pythonRuntimeProbe;
    if (active != null) return active;
    late final Future<_PythonRuntimeScan?> probe;
    probe = _resolvePythonRuntimeUncached().whenComplete(() {
      if (identical(_pythonRuntimeProbe, probe)) {
        _pythonRuntimeProbe = null;
      }
    });
    _pythonRuntimeProbe = probe;
    return probe;
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
      id: 'python',
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
          environment: _proxyEnv(),
        );
        final version = versionResult.exitCode == 0
            ? versionResult.stdout.toString().trim()
            : nvm.version;
        final latestVersion = await _queryLatestNodeVersion(
          installedVersion: version,
          releaseHint: _readNvmDefaultAlias(),
        );
        return PluginInfo(
          id: 'nodejs',
          name: 'Node.js',
          description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
          status: PluginStatus.installed,
          installedVersion: version,
          latestVersion: _pickHigherNodeVersion(version, latestVersion),
          installPath: nvm.nodeBin,
          dependents: const ['playwright'],
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
            ? _extractAbsolutePath(pathResult.stdout.toString())
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
          id: 'nodejs',
          name: 'Node.js',
          description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
          status: PluginStatus.installed,
          installedVersion: version,
          latestVersion: _pickHigherNodeVersion(version, latestVersion),
          installPath: installPath?.isEmpty == true ? null : installPath,
          dependents: const ['playwright'],
        );
      }
    } catch (e) {
      silentLog('PluginScanner', 'scanNodeJs', e);
    }
    return _nodeNotInstalled;
  }

  Future<PluginInfo> scanPython() => _runWithFallback(
    operation: 'scanPython',
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
      environment: _proxyEnv(),
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
      id: 'pip',
      name: 'pip',
      description: 'Python 包管理工具，用于安装、升级与管理 Python 库',
      status: PluginStatus.installed,
      installedVersion: version,
      latestVersion: latestVersion,
      installPath: runtime.executable,
      dependencies: const ['python'],
      supportsUninstall: false,
    );
  }

  Future<PluginInfo> scanPip() => _runWithFallback(
    operation: 'scanPip',
    fallback: _pipNotInstalled,
    operationBody: () async =>
        _scanPipWithRuntime(await _resolvePythonRuntime()),
  );

  Future<PluginInfo> scanPlaywright() async {
    try {
      final npxCheck = await _shellRun('which npx');
      if (npxCheck.exitCode != 0) {
        return _playwrightNotInstalled;
      }
      final versionResult = await _shellRun('npx playwright --version');
      if (versionResult.exitCode == 0) {
        final output = versionResult.stdout.toString().trim();
        final version = output
            .replaceFirst(_playwrightVersionPrefixPattern, '')
            .trim();
        String? latestVersion;
        try {
          final r = await _shellRun('npm view playwright version');
          if (r.exitCode == 0) {
            final m = _semverSearchPattern.firstMatch(r.stdout.toString());
            if (m != null) latestVersion = m.group(1);
          }
        } catch (error, stack) {
          silentLog(
            'plugin_scanner',
            'npm view playwright version',
            error,
            stack,
          );
        }
        return PluginInfo(
          id: 'playwright',
          name: 'Playwright',
          description: '浏览器自动化测试框架，支持 Chromium / Firefox / WebKit',
          status: PluginStatus.installed,
          installedVersion: version,
          latestVersion: latestVersion,
          dependencies: const ['nodejs'],
        );
      }
    } catch (e) {
      silentLog('PluginScanner', 'scanPlaywright', e);
    }
    return _playwrightNotInstalled;
  }

  Future<PluginInfo> scanHermesAgent() => _runWithFallback(
    operation: 'scanHermesAgent',
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

  Future<PluginInfo> scanJava() => _runWithFallback(
    operation: 'scanJava',
    fallback: _javaNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: 'java',
      name: 'Java',
      description: 'JDK 运行时，用于 apktool / jadx 等 Android 静态分析工具',
      commands: const <String>['java'],
      versionArgs: const <String>['-version'],
      versionParser: _extractJavaVersion,
      latestBrewFormula: 'openjdk',
      dependents: const <String>['apktool', 'jadx'],
    ),
  );

  Future<PluginInfo> scanFrida() => _runWithFallback(
    operation: 'scanFrida',
    fallback: _fridaNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: 'frida',
      name: 'Frida',
      description: '动态插桩与 Hook 工具链，用于 Android 运行时验证',
      commands: const <String>['frida'],
      versionArgs: const <String>['--version'],
      versionParser: _extractLooseVersion,
      latestPypiPackage: 'frida-tools',
      dependencies: const <String>['python', 'pip'],
    ),
  );

  Future<PluginInfo> scanMitmproxy() => _runWithFallback(
    operation: 'scanMitmproxy',
    fallback: _mitmproxyNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: 'mitmproxy',
      name: 'mitmproxy',
      description: 'HTTP(S) 代理抓包工具，用于 Web / Android 流量取证',
      commands: const <String>['mitmdump', 'mitmproxy'],
      versionArgs: const <String>['--version'],
      versionParser: _extractLooseVersion,
      latestBrewFormula: 'mitmproxy',
    ),
  );

  Future<PluginInfo> scanApktool() => _runWithFallback(
    operation: 'scanApktool',
    fallback: _apktoolNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: 'apktool',
      name: 'apktool',
      description: 'APK 解包与 smali 分析工具',
      commands: const <String>['apktool'],
      versionArgs: const <String>['--version'],
      versionParser: _extractLooseVersion,
      latestBrewFormula: 'apktool',
      dependencies: const <String>['java'],
    ),
  );

  Future<PluginInfo> scanJadx() => _runWithFallback(
    operation: 'scanJadx',
    fallback: _jadxNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: 'jadx',
      name: 'jadx',
      description: 'DEX / APK Java 反编译工具',
      commands: const <String>['jadx'],
      versionArgs: const <String>['--version'],
      versionParser: _extractLooseVersion,
      latestBrewFormula: 'jadx',
      dependencies: const <String>['java'],
    ),
  );

  Future<PluginInfo> scanRadare2() => _runWithFallback(
    operation: 'scanRadare2',
    fallback: _radare2NotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: 'radare2',
      name: 'radare2',
      description: '二进制静态分析与 ELF / native so 逆向工具',
      commands: const <String>['r2', 'radare2'],
      versionArgs: const <String>['-v'],
      versionParser: _extractLooseVersion,
      latestBrewFormula: 'radare2',
    ),
  );

  Future<PluginInfo> scanBlutter() => _runWithFallback(
    operation: 'scanBlutter',
    fallback: _blutterNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: 'blutter',
      name: 'blutter',
      description: 'Flutter Dart AOT 快速还原工具，用于 libapp.so 分析',
      commands: <String>['blutter', _openHandToolBin('blutter')],
      versionArgs: const <String>['--help'],
      versionParser: (_) => null,
      dependencies: const <String>['python', 'pip'],
    ),
  );

  Future<PluginInfo> scanDoldrums() => _runWithFallback(
    operation: 'scanDoldrums',
    fallback: _doldrumsNotInstalled,
    operationBody: () => _scanCommandPlugin(
      id: 'doldrums',
      name: 'Doldrums',
      description: 'Flutter snapshot / ELF 辅助分析工具',
      commands: <String>['doldrums', 'Doldrums', _openHandToolBin('doldrums')],
      versionArgs: const <String>['--help'],
      versionParser: (_) => null,
      dependencies: const <String>['python', 'pip'],
    ),
  );

  Future<PluginInfo> scanAnythingAnalyzer() => _runWithFallback(
    operation: 'scanAnythingAnalyzer',
    fallback: _anythingAnalyzerNotInstalled,
    operationBody: () async {
      final commandScan = await _scanCommandPlugin(
        id: 'anything_analyzer',
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
        if (Directory(path).existsSync() || File(path).existsSync()) {
          return PluginInfo(
            id: 'anything_analyzer',
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
      final desktopAppExists =
          Platform.isMacOS &&
          (Directory('/Applications/Docker.app').existsSync() ||
              Directory(
                '${Platform.environment['HOME'] ?? ''}/Applications/Docker.app',
              ).existsSync());
      if (pathResult.exitCode != 0) {
        if (desktopAppExists) {
          return const PluginInfo(
            id: 'docker',
            name: 'Docker',
            description: '容器运行环境，用于运行 Qdrant 本地向量数据库服务',
            status: PluginStatus.error,
            dependents: <String>['qdrant'],
            metadata: <String, Object?>{
              'desktop_app_detected': true,
              'daemon_running': false,
            },
            errorMessage: '检测到 Docker Desktop，但 docker CLI 不在 PATH 中。',
          );
        }
        return _dockerNotInstalled;
      }
      final installPath = _extractAbsolutePath(pathResult.stdout.toString());
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
          id: 'docker',
          name: 'Docker',
          description: '容器运行环境，用于运行 Qdrant 本地向量数据库服务',
          status: PluginStatus.installed,
          installedVersion: version,
          installPath: installPath,
          dependents: const <String>['qdrant'],
          metadata: metadata,
        );
      }
      return PluginInfo(
        id: 'docker',
        name: 'Docker',
        description: '容器运行环境，用于运行 Qdrant 本地向量数据库服务',
        status: PluginStatus.error,
        installedVersion: version,
        installPath: installPath,
        dependents: const <String>['qdrant'],
        metadata: metadata,
        errorMessage: 'docker CLI 可用，但 Docker daemon 未运行或不可访问。',
      );
    } catch (e, stack) {
      silentLog('PluginScanner', 'scanDocker', e, stack);
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
        'docker inspect ${_shellQuote(qdrantContainerName)}',
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
          : imageVersion;
      if (!openHandManaged) {
        return PluginInfo(
          id: 'qdrant',
          name: 'Qdrant',
          description: '本地向量数据库，用于知识库 embedding 向量索引与检索',
          status: PluginStatus.error,
          installedVersion: installedVersion,
          dependencies: const <String>['docker'],
          metadata: metadata,
          errorMessage: '检测到同名 Qdrant 容器，但缺少 OpenHand 管理标记。',
        );
      }
      if (!running) {
        return PluginInfo(
          id: 'qdrant',
          name: 'Qdrant',
          description: '本地向量数据库，用于知识库 embedding 向量索引与检索',
          status: PluginStatus.error,
          installedVersion: installedVersion,
          dependencies: const <String>['docker'],
          metadata: metadata,
          errorMessage: 'OpenHand Qdrant 容器已存在但未运行。',
        );
      }
      return PluginInfo(
        id: 'qdrant',
        name: 'Qdrant',
        description: '本地向量数据库，用于知识库 embedding 向量索引与检索',
        status: PluginStatus.installed,
        installedVersion: installedVersion,
        installPath: '${metadata['data_directory'] ?? ''}'.trim().isEmpty
            ? null
            : '${metadata['data_directory']}',
        dependencies: const <String>['docker'],
        metadata: metadata,
      );
    } catch (e, stack) {
      silentLog('PluginScanner', 'scanQdrant', e, stack);
    }
    return _qdrantNotInstalled;
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

  static String _extractHostDataDirectory(Object? mounts) {
    if (mounts is! List) return '';
    for (final mount in mounts) {
      if (mount is! Map) continue;
      final mountMap = stringKeyedMapFromValue(mount);
      final destination = '${mountMap['Destination'] ?? ''}'.trim();
      if (destination == '/qdrant/storage') {
        return '${mountMap['Source'] ?? ''}'.trim();
      }
    }
    return '';
  }

  static String _openHandToolBin(String name) {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.openhand/android_reverse_tools/bin/$name';
  }

  static List<String> _anythingAnalyzerAppCandidates() {
    final home = Platform.environment['HOME'] ?? '';
    return <String>[
      '/Applications/Anything Analyzer.app',
      '$home/Applications/Anything Analyzer.app',
      '$home/.openhand/android_reverse_tools/anything-analyzer/Anything Analyzer.app',
    ];
  }

  static const _nodeNotInstalled = PluginInfo(
    id: 'nodejs',
    name: 'Node.js',
    description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
    status: PluginStatus.notInstalled,
    dependents: [PluginCatalogIds.playwright, PluginCatalogIds.hermesAgent],
  );

  static const _playwrightNotInstalled = PluginInfo(
    id: 'playwright',
    name: 'Playwright',
    description: '浏览器自动化测试框架，支持 Chromium / Firefox / WebKit',
    status: PluginStatus.notInstalled,
    dependencies: ['nodejs'],
  );

  static const _hermesAgentNotInstalled = PluginInfo(
    id: PluginCatalogIds.hermesAgent,
    name: 'Hermes Agent',
    description: 'Hermes Agent 运行时，用于智能体编排、自我学习与技能沉淀',
    status: PluginStatus.notInstalled,
    dependencies: [PluginCatalogIds.nodejs],
  );

  static const _pythonNotInstalled = PluginInfo(
    id: 'python',
    name: 'Python',
    description: 'Python 运行时环境，用于执行 Python 脚本、库与扩展能力',
    status: PluginStatus.notInstalled,
  );

  static const _pipNotInstalled = PluginInfo(
    id: 'pip',
    name: 'pip',
    description: 'Python 包管理工具，用于安装、升级与管理 Python 库',
    status: PluginStatus.notInstalled,
    dependencies: ['python'],
    supportsUninstall: false,
  );

  static const _javaNotInstalled = PluginInfo(
    id: 'java',
    name: 'Java',
    description: 'JDK 运行时，用于 apktool / jadx 等 Android 静态分析工具',
    status: PluginStatus.notInstalled,
    dependents: ['apktool', 'jadx'],
  );

  static const _fridaNotInstalled = PluginInfo(
    id: 'frida',
    name: 'Frida',
    description: '动态插桩与 Hook 工具链，用于 Android 运行时验证',
    status: PluginStatus.notInstalled,
    dependencies: ['python', 'pip'],
  );

  static const _mitmproxyNotInstalled = PluginInfo(
    id: 'mitmproxy',
    name: 'mitmproxy',
    description: 'HTTP(S) 代理抓包工具，用于 Web / Android 流量取证',
    status: PluginStatus.notInstalled,
  );

  static const _apktoolNotInstalled = PluginInfo(
    id: 'apktool',
    name: 'apktool',
    description: 'APK 解包与 smali 分析工具',
    status: PluginStatus.notInstalled,
    dependencies: ['java'],
  );

  static const _jadxNotInstalled = PluginInfo(
    id: 'jadx',
    name: 'jadx',
    description: 'DEX / APK Java 反编译工具',
    status: PluginStatus.notInstalled,
    dependencies: ['java'],
  );

  static const _radare2NotInstalled = PluginInfo(
    id: 'radare2',
    name: 'radare2',
    description: '二进制静态分析与 ELF / native so 逆向工具',
    status: PluginStatus.notInstalled,
  );

  static const _blutterNotInstalled = PluginInfo(
    id: 'blutter',
    name: 'blutter',
    description: 'Flutter Dart AOT 快速还原工具，用于 libapp.so 分析',
    status: PluginStatus.notInstalled,
    dependencies: ['python', 'pip'],
  );

  static const _doldrumsNotInstalled = PluginInfo(
    id: 'doldrums',
    name: 'Doldrums',
    description: 'Flutter snapshot / ELF 辅助分析工具',
    status: PluginStatus.notInstalled,
    dependencies: ['python', 'pip'],
  );

  static const _anythingAnalyzerNotInstalled = PluginInfo(
    id: 'anything_analyzer',
    name: 'Anything Analyzer',
    description: '协议分析与 MCP Server 工具，用于抓包、分析和 Agent 联动',
    status: PluginStatus.notInstalled,
  );

  static const _dockerNotInstalled = PluginInfo(
    id: 'docker',
    name: 'Docker',
    description: '容器运行环境，用于运行 Qdrant 本地向量数据库服务',
    status: PluginStatus.notInstalled,
    dependents: ['qdrant'],
  );

  static const _qdrantNotInstalled = PluginInfo(
    id: 'qdrant',
    name: 'Qdrant',
    description: '本地向量数据库，用于知识库 embedding 向量索引与检索',
    status: PluginStatus.notInstalled,
    dependencies: ['docker'],
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
    _hermesAgentNotInstalled,
  ];

  Future<List<PluginInfo>> scanAll() async {
    final nodeFuture = scanNodeJs();
    final playwrightFuture = scanPlaywright();
    final hermesAgentFuture = scanHermesAgent();
    final javaFuture = scanJava();
    final fridaFuture = scanFrida();
    final mitmproxyFuture = scanMitmproxy();
    final apktoolFuture = scanApktool();
    final jadxFuture = scanJadx();
    final radare2Future = scanRadare2();
    final blutterFuture = scanBlutter();
    final doldrumsFuture = scanDoldrums();
    final anythingAnalyzerFuture = scanAnythingAnalyzer();
    final dockerFuture = scanDocker();
    final pythonRuntimeFuture = _resolvePythonRuntime();
    final nodeJs = await nodeFuture;
    final playwright = await playwrightFuture;
    final hermesAgent = await hermesAgentFuture;
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
    final pythonRuntime = await _runWithFallback<_PythonRuntimeScan?>(
      operation: 'resolvePythonRuntime',
      fallback: null,
      operationBody: () => pythonRuntimeFuture,
    );
    final python = _pythonInfoFromRuntime(pythonRuntime);
    final pip = await _runWithFallback(
      operation: 'scanPip',
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
      dependents: qdrant.isInstalled ? const ['qdrant'] : const [],
    );
    final updatedJava = java.copyWith(
      dependents: <String>[
        if (apktool.isInstalled) 'apktool',
        if (jadx.isInstalled) 'jadx',
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
      hermesAgent,
    ];
  }
}

enum _PythonRuntimeSource { pyenv, homebrew, system, unknown }

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
