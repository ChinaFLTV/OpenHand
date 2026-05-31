import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../model/plugin_info.dart';

/// 扫描本机已安装的插件（NodeJS / Playwright / Python / pip），检测版本与可用性。
///
/// 对于 nvm / pyenv 用户，优先直接解析或借助管理器拿到真实可执行路径，
/// 避免 GUI 应用进程 PATH 与终端不一致的问题。
class PluginScannerService {
  PluginScannerService();

  static String _pickShell() {
    final shell = Platform.environment['SHELL'];
    if (shell != null && shell.isNotEmpty) return shell;
    return '/bin/zsh';
  }

  /// 通过 shell 执行命令（用于 fnm/volta/brew/pyenv 等场景）。
  Future<ProcessResult> _shellRun(String command) {
    final home = Platform.environment['HOME'] ?? '';
    final script = StringBuffer();
    script.writeln('export NVM_DIR="\${NVM_DIR:-$home/.nvm}"');
    script.writeln('[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"');
    script.writeln(
      'if command -v fnm >/dev/null 2>&1; then eval "\$(fnm env)"; fi',
    );
    script.writeln('export VOLTA_HOME="\${VOLTA_HOME:-$home/.volta}"');
    script.writeln('export PYENV_ROOT="\${PYENV_ROOT:-$home/.pyenv}"');
    script.writeln(
      'export PATH="\$PYENV_ROOT/bin:/opt/homebrew/bin:/usr/local/bin:\$VOLTA_HOME/bin:\$PATH"',
    );
    script.writeln(
      'if command -v pyenv >/dev/null 2>&1; then eval "\$(pyenv init -)"; fi',
    );
    script.writeln(command);
    return runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', script.toString()],
      timeout: const Duration(seconds: 15),
      tag: 'plugin_scanner.shell_probe',
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
    } catch (_) {}
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
    } catch (_) {
      return null;
    }
    if (versions.isEmpty) return null;
    versions.sort(_compareNodeVersions);

    final alias = _readNvmDefaultAlias();

    String resolvedVersion;
    if (alias == 'node' || alias == 'stable' || alias == 'current') {
      resolvedVersion = versions.last;
    } else if (alias.startsWith('lts')) {
      resolvedVersion = versions.lastWhere(
        (v) => (int.tryParse(v.substring(1).split('.').first) ?? 0).isEven,
        orElse: () => versions.last,
      );
    } else if (RegExp(r'^v?\d+$').hasMatch(alias)) {
      final major = alias.replaceFirst('v', '');
      resolvedVersion = versions.lastWhere(
        (v) => v.substring(1).split('.').first == major,
        orElse: () => versions.last,
      );
    } else if (RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(alias)) {
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

  static int _compareNodeVersions(String a, String b) {
    final ap = a
        .substring(1)
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final bp = b
        .substring(1)
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    for (int i = 0; i < 3; i++) {
      final av = i < ap.length ? ap[i] : 0;
      final bv = i < bp.length ? bp[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static int _compareSemver(String a, String b) {
    final ap = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bp = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final maxLength = ap.length > bp.length ? ap.length : bp.length;
    for (int i = 0; i < maxLength; i++) {
      final av = i < ap.length ? ap[i] : 0;
      final bv = i < bp.length ? bp[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static bool _isSemanticVersion(String value) {
    return RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value);
  }

  static String? _extractAbsolutePath(String output) {
    for (final line in output.split('\n').reversed) {
      final trimmed = line.trim();
      if (trimmed.startsWith('/')) return trimmed;
    }
    return null;
  }

  static String? _extractVersion(String output) {
    final match = RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(output);
    return match?.group(0);
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
    try {
      final decoded = jsonDecode(result.stdout.toString());
      if (decoded is! List) return null;
      for (final entry in decoded) {
        if (entry is! Map<String, Object?>) continue;
        final version = entry['version'];
        if (version is! String || !_isNodeVersion(version)) continue;
        final lts = entry['lts'];
        final isLts = lts is String && lts.isNotEmpty;
        if (preferLts ? isLts : !isLts) return version;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static int? _extractNodeMajor(String version) {
    final match = RegExp(r'v?(\d+)').firstMatch(version);
    return int.tryParse(match?.group(1) ?? '');
  }

  static bool _isNodeVersion(String value) {
    return RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(value);
  }

  static String? _pickHigherNodeVersion(
    String installedVersion,
    String? candidateLatestVersion,
  ) {
    if (candidateLatestVersion == null || candidateLatestVersion.isEmpty) {
      return null;
    }
    return _compareNodeVersions(candidateLatestVersion, installedVersion) > 0
        ? candidateLatestVersion
        : null;
  }

  static String? _extractPythonVersion(String output) {
    final match = RegExp(r'Python\s+(\d+\.\d+\.\d+)').firstMatch(output);
    return match?.group(1);
  }

  static String? _extractPipVersion(String output) {
    final match = RegExp(r'pip\s+(\d+(?:\.\d+)+)').firstMatch(output);
    return match?.group(1);
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
    final match = RegExp(r'/.pyenv/versions/([^/]+)/').firstMatch(path);
    final value = match?.group(1);
    if (value != null && _isSemanticVersion(value)) return value;
    return null;
  }

  static String? _extractBrewPythonFormulaFromPath(String path) {
    final matches = RegExp(r'/(python(?:@[\d.]+)?)(?:/|$)').allMatches(path);
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
    versions.sort(_compareSemver);
    return versions.last;
  }

  Future<String?> _queryBrewLatestVersion(String formula) async {
    final result = await _shellRun('brew info --json=v2 $formula');
    if (result.exitCode != 0) return null;
    try {
      final decoded = jsonDecode(result.stdout.toString());
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
    } catch (_) {
      return null;
    }
  }

  Future<String?> _queryLatestPipVersion() async {
    final result = await _shellRun('curl -fsSL https://pypi.org/pypi/pip/json');
    if (result.exitCode != 0) return null;
    try {
      final decoded = jsonDecode(result.stdout.toString());
      if (decoded is! Map<String, Object?>) return null;
      final info = decoded['info'];
      if (info is! Map<String, Object?>) return null;
      final version = info['version'];
      return version is String && version.isNotEmpty ? version : null;
    } catch (_) {
      return null;
    }
  }

  static String? _extractFirstSemver(String output, {String? prefix}) {
    final matches = RegExp(r'(\d+\.\d+\.\d+)').allMatches(output);
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
    for (final match in RegExp(r'^\s*(\d+\.\d+\.\d+)\s*$').allMatches(output)) {
      final value = match.group(1);
      if (value == null) continue;
      if (prefix != null && !value.startsWith(prefix)) continue;
      versions.add(value);
    }
    return versions.toList(growable: false);
  }

  Future<_PythonRuntimeScan?> _resolvePyenvPython() async {
    final versionNameResult = await _shellRun('pyenv version-name');
    final selectedVersionName = versionNameResult.exitCode == 0
        ? versionNameResult.stdout.toString().trim().split(RegExp(r'\s+')).first
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
      );
      if (versionResult.exitCode != 0) continue;
      final version = _extractPythonVersion(
        '${versionResult.stdout}\n${versionResult.stderr}',
      );
      if (version == null) continue;
      final managedPyenvVersion =
          (selectedVersionName != null &&
              _isSemanticVersion(selectedVersionName))
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
      final version = _extractPythonVersion(
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

  Future<PluginInfo> scanNodeJs() async {
    try {
      final nvm = await _resolveNvmDirect();
      if (nvm != null) {
        final versionResult = await runTrackedProcessOrFailed(nvm.nodeBin, [
          '--version',
        ], timeout: const Duration(seconds: 5));
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

  Future<PluginInfo> scanPython() async {
    try {
      final pyenvAvailable = await _isPyenvAvailable();
      final runtime = pyenvAvailable
          ? await _resolvePyenvPython()
          : await _resolveShellPython();
      final resolvedRuntime = runtime ?? await _resolveShellPython();
      if (resolvedRuntime == null) return _pythonNotInstalled;
      return PluginInfo(
        id: 'python',
        name: 'Python',
        description: 'Python 运行时环境，用于执行 Python 脚本、库与扩展能力',
        status: PluginStatus.installed,
        installedVersion: resolvedRuntime.version,
        latestVersion: resolvedRuntime.latestVersion,
        installPath: resolvedRuntime.executable,
      );
    } catch (e) {
      silentLog('PluginScanner', 'scanPython', e);
    }
    return _pythonNotInstalled;
  }

  Future<PluginInfo> scanPip() async {
    try {
      final pyenvAvailable = await _isPyenvAvailable();
      final runtime = pyenvAvailable
          ? await _resolvePyenvPython()
          : await _resolveShellPython();
      final resolvedRuntime = runtime ?? await _resolveShellPython();
      if (resolvedRuntime == null) return _pipNotInstalled;
      final pipVersionResult = await runTrackedProcessOrFailed(
        resolvedRuntime.executable,
        ['-m', 'pip', '--version'],
        timeout: const Duration(seconds: 8),
        tag: 'plugin_scanner.pip_probe',
      );
      if (pipVersionResult.exitCode != 0) {
        return _pipNotInstalled;
      }
      final version = _extractPipVersion(
        '${pipVersionResult.stdout}\n${pipVersionResult.stderr}',
      );
      if (version == null) return _pipNotInstalled;
      final latestVersion = switch (resolvedRuntime.source) {
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
        installPath: resolvedRuntime.executable,
        dependencies: const ['python'],
        supportsUninstall: false,
      );
    } catch (e) {
      silentLog('PluginScanner', 'scanPip', e);
    }
    return _pipNotInstalled;
  }

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
            .replaceFirst(RegExp(r'^Version\s+', caseSensitive: false), '')
            .trim();
        String? latestVersion;
        try {
          final r = await _shellRun('npm view playwright version');
          if (r.exitCode == 0) {
            final m = RegExp(
              r'(\d+\.\d+\.\d+)',
            ).firstMatch(r.stdout.toString());
            if (m != null) latestVersion = m.group(1);
          }
        } catch (_) {}
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

  static const _nodeNotInstalled = PluginInfo(
    id: 'nodejs',
    name: 'Node.js',
    description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
    status: PluginStatus.notInstalled,
    dependents: ['playwright'],
  );

  static const _playwrightNotInstalled = PluginInfo(
    id: 'playwright',
    name: 'Playwright',
    description: '浏览器自动化测试框架，支持 Chromium / Firefox / WebKit',
    status: PluginStatus.notInstalled,
    dependencies: ['nodejs'],
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

  Future<List<PluginInfo>> scanAll() async {
    final results = await Future.wait([
      scanNodeJs(),
      scanPlaywright(),
      scanPython(),
      scanPip(),
    ]);
    final nodeJs = results[0];
    final playwright = results[1];
    final python = results[2];
    final pip = results[3];
    final updatedNodeJs = nodeJs.copyWith(
      dependents: playwright.isInstalled ? const ['playwright'] : const [],
    );
    return [updatedNodeJs, playwright, python, pip];
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
