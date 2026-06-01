import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/system_proxy.dart';

/// 插件生命周期操作结果。
class PluginOperationResult {
  const PluginOperationResult({
    required this.success,
    this.message,
    this.newVersion,
  });

  final bool success;
  final String? message;
  final String? newVersion;
}

/// 管理插件的安装、更新、卸载操作。
///
/// 处理依赖关系：
/// - 安装 Playwright 前自动检查 NodeJS 是否已安装
/// - 卸载 NodeJS 前检查 Playwright 是否仍在使用
/// - Python / pip 仅自动管理 pyenv 与 Homebrew 来源
class PluginLifecycleService {
  PluginLifecycleService();

  static String _pickShell() {
    final shell = Platform.environment['SHELL'];
    if (shell != null && shell.isNotEmpty) return shell;
    return '/bin/zsh';
  }

  /// 把 SystemProxyResolver 解析出的代理端点叠加到子进程环境。
  /// 任何需要访问外网（PyPI / npm / Homebrew bottles / Node release /
  /// ghcr.io 等）的子流程都必须走这条通道，否则在企业代理 / 内网
  /// 透明代理环境下 install / update 会因 TCP 握手失败而超时。
  static Map<String, String> _proxyEnv() {
    return SystemProxyResolver.instance.resolveSubprocessEnvironment();
  }

  /// nvm 是 shell 函数而非可执行文件，需要先 source 初始化脚本。
  static String _nvmSourcePrefix() {
    final home = Platform.environment['HOME'] ?? '';
    return '''
export NVM_DIR="\${NVM_DIR:-$home/.nvm}"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
''';
  }

  static String _pythonShellPrefix() {
    final home = Platform.environment['HOME'] ?? '';
    return '''
export PYENV_ROOT="\${PYENV_ROOT:-$home/.pyenv}"
export PATH="\$PYENV_ROOT/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"
if command -v pyenv >/dev/null 2>&1; then
  eval "\$(pyenv init -)"
fi
''';
  }

  Future<_SimpleProcessResult> _runNvmCommand(
    String nvmCommand, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) {
    final script = '${_nvmSourcePrefix()}$nvmCommand';
    return _runWithProgress(
      _pickShell(),
      ['-c', script],
      onProgress: onProgress,
      timeout: timeout,
      environment: _proxyEnv(),
    );
  }

  Future<_SimpleProcessResult> _runPythonShellCommand(
    String command, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) {
    final script = '${_pythonShellPrefix()}$command';
    return _runWithProgress(
      _pickShell(),
      ['-c', script],
      onProgress: onProgress,
      timeout: timeout,
      environment: _proxyEnv(),
    );
  }

  Future<_SimpleProcessResult> _runBoundPythonCommand(
    String executable,
    List<String> arguments, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) {
    return _runWithProgress(
      executable,
      arguments,
      onProgress: onProgress,
      timeout: timeout,
      environment: _proxyEnv(),
    );
  }

  Future<bool> _isNvmAvailable() async {
    final home = Platform.environment['HOME'] ?? '';
    final nvmSh = File('$home/.nvm/nvm.sh');
    return nvmSh.existsSync();
  }

  Future<bool> _isPyenvAvailable() async {
    final home = Platform.environment['HOME'] ?? '';
    if (File('$home/.pyenv/bin/pyenv').existsSync()) return true;
    final result = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}command -v pyenv'],
      timeout: const Duration(seconds: 5),
      tag: 'plugin_lifecycle.pyenv_check',
    );
    return result.exitCode == 0;
  }

  Future<_PythonRuntimeContext?> _detectPythonRuntimeContext() async {
    final pyenvContext = await _detectPyenvContext();
    if (pyenvContext != null) return pyenvContext;
    final brewContext = await _detectBrewPythonContext();
    if (brewContext != null) return brewContext;
    final pythonPath = await _resolveActivePythonPath();
    if (pythonPath == null) return null;
    return _PythonRuntimeContext(
      source: _looksLikeSystemPython(pythonPath)
          ? _PythonRuntimeSource.system
          : _PythonRuntimeSource.unknown,
      executablePath: pythonPath,
      version: await _readPythonVersion(pythonPath),
    );
  }

  Future<_PythonRuntimeContext?> _detectPyenvContext() async {
    if (!await _isPyenvAvailable()) return null;
    final versionNameResult = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}pyenv version-name'],
      timeout: const Duration(seconds: 5),
      tag: 'plugin_lifecycle.pyenv_version_name',
    );
    final selected = versionNameResult.exitCode == 0
        ? versionNameResult.stdout.toString().trim().split(RegExp(r'\s+')).first
        : null;
    final executable = await _resolvePyenvPythonPath();
    if (executable == null) return null;
    final managedPyenvVersion = selected != null && _isSemanticVersion(selected)
        ? selected
        : _extractPyenvVersionFromPath(executable);
    if (managedPyenvVersion == null) return null;
    final version = await _readPythonVersion(executable);
    return _PythonRuntimeContext(
      source: _PythonRuntimeSource.pyenv,
      executablePath: executable,
      version: version,
      pyenvVersion: managedPyenvVersion,
    );
  }

  Future<_PythonRuntimeContext?> _detectBrewPythonContext() async {
    final executable = await _resolveActivePythonPath();
    if (executable == null || !_looksLikeHomebrewPath(executable)) return null;
    final version = await _readPythonVersion(executable);
    return _PythonRuntimeContext(
      source: _PythonRuntimeSource.homebrew,
      executablePath: executable,
      version: version,
      brewFormula: _extractBrewPythonFormulaFromPath(executable) ?? 'python',
    );
  }

  Future<String?> _resolveActivePythonPath() async {
    final result = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}command -v python3 || command -v python'],
      timeout: const Duration(seconds: 5),
      tag: 'plugin_lifecycle.python_path',
    );
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split('\n').reversed) {
      final trimmed = line.trim();
      if (trimmed.startsWith('/')) return trimmed;
    }
    return null;
  }

  Future<String?> _resolvePyenvPythonPath() async {
    for (final command in const ['python3', 'python']) {
      final result = await runTrackedProcessOrFailed(
        _pickShell(),
        ['-c', '${_pythonShellPrefix()}pyenv which $command'],
        timeout: const Duration(seconds: 5),
        tag: 'plugin_lifecycle.pyenv_which',
      );
      if (result.exitCode != 0) continue;
      for (final line in result.stdout.toString().split('\n').reversed) {
        final trimmed = line.trim();
        if (trimmed.startsWith('/')) return trimmed;
      }
    }
    return null;
  }

  Future<String?> _readPythonVersion(String executable) async {
    final result = await runTrackedProcessOrFailed(
      executable,
      ['--version'],
      timeout: const Duration(seconds: 5),
      tag: 'plugin_lifecycle.python_version',
    );
    if (result.exitCode != 0) return null;
    return _extractPythonVersion('${result.stdout}\n${result.stderr}');
  }

  Future<String?> _readPipVersion(String executable) async {
    final result = await runTrackedProcessOrFailed(
      executable,
      ['-m', 'pip', '--version'],
      timeout: const Duration(seconds: 8),
      tag: 'plugin_lifecycle.pip_version',
    );
    if (result.exitCode != 0) return null;
    return _extractPipVersion('${result.stdout}\n${result.stderr}');
  }

  bool _isExternallyManagedPipError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('externally-managed-environment') ||
        normalized.contains('externally managed') ||
        normalized.contains('pep 668');
  }

  String _pipManagedEnvironmentMessage(_PythonRuntimeContext context) {
    return switch (context.source) {
      _PythonRuntimeSource.homebrew =>
        '当前 pip 由 Homebrew Python 管理，不能在插件中直接自升级。请通过 Homebrew 更新对应 Python。',
      _PythonRuntimeSource.system =>
        '当前 pip 绑定的是系统 Python，不能在插件中直接自升级。若需安装第三方库，请使用虚拟环境。',
      _PythonRuntimeSource.unknown =>
        '当前 pip 绑定的 Python 来源未知，不能安全地在插件中直接自升级。若需安装第三方库，请使用虚拟环境。',
      _ => '当前 pip 所在环境不支持在插件中直接自升级。',
    };
  }

  Future<String?> _queryLatestPyenvPatch(String currentVersion) async {
    final parts = currentVersion.split('.');
    if (parts.length < 2) return null;
    final majorMinor = '${parts[0]}.${parts[1]}';
    final proxyEnv = _proxyEnv();
    final latestResult = await runTrackedProcessOrFailed(
      _pickShell(),
      [
        '-c',
        '${_pythonShellPrefix()}pyenv latest -k $majorMinor 2>/dev/null || true',
      ],
      timeout: const Duration(seconds: 8),
      tag: 'plugin_lifecycle.pyenv_latest',
      environment: proxyEnv,
    );
    final quickVersion = _extractFirstSemver(
      '${latestResult.stdout}\n${latestResult.stderr}',
      prefix: '$majorMinor.',
    );
    if (quickVersion != null) return quickVersion;

    final listResult = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}pyenv install --list'],
      timeout: const Duration(seconds: 15),
      tag: 'plugin_lifecycle.pyenv_list',
      environment: proxyEnv,
    );
    if (listResult.exitCode != 0) return null;
    final versions = _extractStablePyenvVersions(
      listResult.stdout.toString(),
      prefix: '$majorMinor.',
    );
    if (versions.isEmpty) return null;
    versions.sort(_compareSemver);
    return versions.last;
  }

  Future<String?> _queryLatestHomebrewVersion(String formula) async {
    final result = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}brew info --json=v2 $formula'],
      timeout: const Duration(seconds: 10),
      tag: 'plugin_lifecycle.brew_info',
      environment: _proxyEnv(),
    );
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

  Future<PluginOperationResult> installNodeJs({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测可用的包管理器…');

    if (await _isNvmAvailable()) {
      onProgress?.call('使用 nvm 安装 Node.js…');
      final result = await _runNvmCommand(
        'nvm install node && nvm alias default node && node --version',
        onProgress: onProgress,
      );
      if (result.exitCode == 0) {
        final lines = result.stdout
            .split('\n')
            .map((l) => l.trim())
            .where(
              (l) => l.startsWith('v') && RegExp(r'^v\d+\.\d+').hasMatch(l),
            )
            .toList();
        final version = lines.isNotEmpty ? lines.last : '';
        if (version.isNotEmpty) {
          onProgress?.call('Node.js $version 安装成功');
          return PluginOperationResult(
            success: true,
            message: 'Node.js $version 已通过 nvm 安装',
            newVersion: version,
          );
        }
        return const PluginOperationResult(
          success: true,
          message: 'Node.js 已通过 nvm 安装',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'nvm 安装失败: ${result.stderr}',
      );
    }

    final fnmCheck = await runTrackedProcessOrFailed('which', [
      'fnm',
    ], timeout: const Duration(seconds: 5));
    if (fnmCheck.exitCode == 0) {
      onProgress?.call('使用 fnm 安装 Node.js LTS…');
      final result = await _runWithProgress(
        'fnm',
        ['install', '--lts'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        await runTrackedProcessOrFailed('fnm', [
          'default',
          'lts-latest',
        ], timeout: const Duration(seconds: 10));
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: const Duration(seconds: 8));
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          onProgress?.call('Node.js $version 安装成功');
          return PluginOperationResult(
            success: true,
            message: 'Node.js $version 已通过 fnm 安装',
            newVersion: version,
          );
        }
      }
      return PluginOperationResult(
        success: false,
        message: 'fnm 安装失败: ${result.stderr}',
      );
    }

    final brewCheck = await runTrackedProcessOrFailed('which', [
      'brew',
    ], timeout: const Duration(seconds: 5));
    if (brewCheck.exitCode == 0) {
      onProgress?.call('使用 Homebrew 安装 Node.js…');
      final result = await _runWithProgress(
        'brew',
        ['install', 'node'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: const Duration(seconds: 8));
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          onProgress?.call('Node.js $version 安装成功');
          return PluginOperationResult(
            success: true,
            message: 'Node.js $version 已通过 Homebrew 安装',
            newVersion: version,
          );
        }
      }
      return PluginOperationResult(
        success: false,
        message: 'Homebrew 安装 Node.js 失败: ${result.stderr}',
      );
    }

    return const PluginOperationResult(
      success: false,
      message:
          '未找到可用的包管理器 (nvm / fnm / brew)。请手动安装 Node.js: https://nodejs.org',
    );
  }

  Future<PluginOperationResult> installPython({
    void Function(String line)? onProgress,
  }) async {
    if (await _isPyenvAvailable()) {
      onProgress?.call('检测到 pyenv，准备安装 Python…');
      final latest = await _queryLatestPyenvPatch('3.12.0') ?? '3.12.11';
      final result = await _runPythonShellCommand(
        'pyenv install -s $latest && pyenv global $latest && python3 --version',
        onProgress: onProgress,
        timeout: const Duration(minutes: 12),
      );
      if (result.exitCode == 0) {
        final version =
            _extractPythonVersion('${result.stdout}\n${result.stderr}') ??
            latest;
        onProgress?.call('Python $version 安装成功');
        return PluginOperationResult(
          success: true,
          message: 'Python $version 已通过 pyenv 安装',
          newVersion: version,
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'pyenv 安装失败: ${result.stderr}',
      );
    }

    final brewCheck = await runTrackedProcessOrFailed('which', [
      'brew',
    ], timeout: const Duration(seconds: 5));
    if (brewCheck.exitCode == 0) {
      onProgress?.call('使用 Homebrew 安装 Python…');
      final result = await _runWithProgress(
        'brew',
        ['install', 'python'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 8),
      );
      if (result.exitCode == 0) {
        final versionResult = await runTrackedProcessOrFailed(
          _pickShell(),
          ['-c', '${_pythonShellPrefix()}python3 --version'],
          timeout: const Duration(seconds: 8),
          tag: 'plugin_lifecycle.python_install_verify',
        );
        final version = _extractPythonVersion(
          '${versionResult.stdout}\n${versionResult.stderr}',
        );
        if (version != null) {
          onProgress?.call('Python $version 安装成功');
          return PluginOperationResult(
            success: true,
            message: 'Python $version 已通过 Homebrew 安装',
            newVersion: version,
          );
        }
        return const PluginOperationResult(
          success: true,
          message: 'Python 已通过 Homebrew 安装',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'Homebrew 安装 Python 失败: ${result.stderr}',
      );
    }

    return const PluginOperationResult(
      success: false,
      message:
          '未找到可自动管理 Python 的包管理器（pyenv / brew）。请先安装 pyenv 或 Homebrew，或手动安装 Python。',
    );
  }

  Future<PluginOperationResult> installPip({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 运行时…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时，请先安装 Python。',
      );
    }

    final existingVersion = await _readPipVersion(context.executablePath);
    if (existingVersion != null &&
        context.source == _PythonRuntimeSource.homebrew) {
      onProgress?.call('检测到 Homebrew 管理的 pip，跳过插件内自升级。');
      return PluginOperationResult(
        success: true,
        message: '当前 pip 由 Homebrew Python 管理，请通过 Homebrew 更新对应 Python。',
        newVersion: existingVersion,
      );
    }

    onProgress?.call('正在引导 pip…');
    final ensureResult = await _runBoundPythonCommand(
      context.executablePath,
      ['-m', 'ensurepip', '--upgrade'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 8),
    );
    if (ensureResult.exitCode != 0) {
      final ensureMessage = ensureResult.stderr.isNotEmpty
          ? ensureResult.stderr
          : ensureResult.stdout;
      if (_isExternallyManagedPipError(ensureMessage)) {
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'pip 引导失败: $ensureMessage',
      );
    }

    if (context.source == _PythonRuntimeSource.pyenv) {
      onProgress?.call('正在升级 pip…');
      final upgradeResult = await _runBoundPythonCommand(
        context.executablePath,
        ['-m', 'pip', 'install', '--upgrade', 'pip'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 8),
      );
      if (upgradeResult.exitCode != 0) {
        final upgradeMessage = upgradeResult.stderr.isNotEmpty
            ? upgradeResult.stderr
            : upgradeResult.stdout;
        if (_isExternallyManagedPipError(upgradeMessage)) {
          return PluginOperationResult(
            success: false,
            message: _pipManagedEnvironmentMessage(context),
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'pip 升级失败: $upgradeMessage',
        );
      }
    }

    final version = await _readPipVersion(context.executablePath);
    if (version == null) {
      return const PluginOperationResult(
        success: false,
        message: 'pip 安装后验证失败',
      );
    }
    onProgress?.call('pip $version 安装成功');
    return PluginOperationResult(
      success: true,
      message: 'pip $version 已就绪',
      newVersion: version,
    );
  }

  Future<PluginOperationResult> installPlaywright({
    void Function(String line)? onProgress,
  }) async {
    final nodeCheck = await runTrackedProcessOrFailed('node', [
      '--version',
    ], timeout: const Duration(seconds: 8));
    if (nodeCheck.exitCode != 0) {
      return const PluginOperationResult(
        success: false,
        message: 'Playwright 依赖 Node.js，请先安装 Node.js',
      );
    }
    onProgress?.call('正在安装 Playwright…');
    final installResult = await _runWithProgress(
      'npm',
      ['install', '-g', 'playwright'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 5),
    );
    if (installResult.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'npm install playwright 失败: ${installResult.stderr}',
      );
    }
    onProgress?.call('正在安装 Playwright 浏览器…');
    await _runWithProgress(
      'npx',
      ['playwright', 'install'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 10),
    );
    final verify = await runTrackedProcessOrFailed('npx', [
      'playwright',
      '--version',
    ], timeout: const Duration(seconds: 15));
    if (verify.exitCode == 0) {
      final version = verify.stdout.toString().trim().replaceFirst(
        RegExp(r'^Version\s+', caseSensitive: false),
        '',
      );
      onProgress?.call('Playwright $version 安装成功');
      return PluginOperationResult(
        success: true,
        message: 'Playwright $version 已安装',
        newVersion: version,
      );
    }
    return const PluginOperationResult(
      success: false,
      message: 'Playwright 安装后验证失败',
    );
  }

  Future<PluginOperationResult> updateNodeJs({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Node.js 安装方式…');
    final whichResult = await runTrackedProcessOrFailed('which', [
      'node',
    ], timeout: const Duration(seconds: 5));
    final nodePath = whichResult.exitCode == 0
        ? whichResult.stdout.toString().trim()
        : '';

    final isNvm = nodePath.contains('.nvm/');
    final isFnm = nodePath.contains('.fnm/') || nodePath.contains('/fnm/');
    final isVolta = nodePath.contains('.volta/');
    final isBrew =
        nodePath.contains('/homebrew/') ||
        nodePath.contains('/Cellar/') ||
        nodePath.startsWith('/opt/homebrew/') ||
        nodePath.startsWith('/usr/local/bin/');

    if (isNvm) {
      onProgress?.call('检测到 nvm 管理的 Node.js，使用 nvm 更新…');
      final result = await _runNvmCommand(
        'nvm install node --reinstall-packages-from=current && nvm alias default node && node --version',
        onProgress: onProgress,
      );
      if (result.exitCode == 0) {
        final lines = result.stdout
            .split('\n')
            .map((l) => l.trim())
            .where(
              (l) => l.startsWith('v') && RegExp(r'^v\d+\.\d+').hasMatch(l),
            )
            .toList();
        final version = lines.isNotEmpty ? lines.last : '';
        if (version.isNotEmpty) {
          onProgress?.call('Node.js 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Node.js 已通过 nvm 更新到 $version',
            newVersion: version,
          );
        }
        onProgress?.call('Node.js 更新完成');
        return const PluginOperationResult(
          success: true,
          message: 'Node.js 已通过 nvm 更新',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'nvm 更新失败: ${result.stderr}',
      );
    }

    if (isFnm) {
      onProgress?.call('检测到 fnm 管理的 Node.js，使用 fnm 更新…');
      final result = await _runWithProgress(
        'fnm',
        ['install', '--lts'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        await runTrackedProcessOrFailed('fnm', [
          'default',
          'lts-latest',
        ], timeout: const Duration(seconds: 10));
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: const Duration(seconds: 8));
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          onProgress?.call('Node.js 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Node.js 已通过 fnm 更新到 $version',
            newVersion: version,
          );
        }
      }
      return PluginOperationResult(
        success: false,
        message: 'fnm 更新失败: ${result.stderr}',
      );
    }

    if (isVolta) {
      onProgress?.call('检测到 volta 管理的 Node.js，使用 volta 更新…');
      final result = await _runWithProgress(
        'volta',
        ['install', 'node@latest'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: const Duration(seconds: 8));
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          onProgress?.call('Node.js 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Node.js 已通过 volta 更新到 $version',
            newVersion: version,
          );
        }
      }
      return PluginOperationResult(
        success: false,
        message: 'volta 更新失败: ${result.stderr}',
      );
    }

    if (isBrew) {
      onProgress?.call('检测到 Homebrew 管理的 Node.js，使用 brew 更新…');
      final result = await _runWithProgress(
        'brew',
        ['upgrade', 'node'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: const Duration(seconds: 8));
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          onProgress?.call('Node.js 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Node.js 已通过 Homebrew 更新到 $version',
            newVersion: version,
          );
        }
      }
      return PluginOperationResult(
        success: false,
        message: 'Homebrew 更新失败: ${result.stderr}',
      );
    }

    onProgress?.call('未能确定安装方式，尝试可用的包管理器…');
    final fnmCheck = await runTrackedProcessOrFailed('which', [
      'fnm',
    ], timeout: const Duration(seconds: 5));
    if (fnmCheck.exitCode == 0) {
      final result = await _runWithProgress(
        'fnm',
        ['install', '--lts'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        await runTrackedProcessOrFailed('fnm', [
          'default',
          'lts-latest',
        ], timeout: const Duration(seconds: 10));
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: const Duration(seconds: 8));
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          return PluginOperationResult(
            success: true,
            message: 'Node.js 已更新到 $version',
            newVersion: version,
          );
        }
      }
    }
    return const PluginOperationResult(
      success: false,
      message:
          '未找到可用的包管理器来更新 Node.js。\n'
          '请根据您的安装方式手动更新：\n'
          '  · nvm: nvm install --lts\n'
          '  · fnm: fnm install --lts\n'
          '  · brew: brew upgrade node\n'
          '  · volta: volta install node@latest',
    );
  }

  Future<PluginOperationResult> updatePython({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 安装方式…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时。',
      );
    }

    switch (context.source) {
      case _PythonRuntimeSource.pyenv:
        final currentVersion = context.version ?? context.pyenvVersion;
        if (currentVersion == null) {
          return const PluginOperationResult(
            success: false,
            message: '无法识别当前 pyenv Python 版本。',
          );
        }
        final latest = await _queryLatestPyenvPatch(currentVersion);
        if (latest == null) {
          return const PluginOperationResult(
            success: false,
            message: '无法查询 pyenv 的最新 Python 版本。',
          );
        }
        if (latest == currentVersion || latest == context.pyenvVersion) {
          return PluginOperationResult(
            success: true,
            message: 'Python 已是最新版本 $currentVersion',
            newVersion: currentVersion,
          );
        }
        onProgress?.call('使用 pyenv 将 Python 更新到 $latest…');
        final result = await _runPythonShellCommand(
          'pyenv install -s $latest && pyenv global $latest && python3 --version',
          onProgress: onProgress,
          timeout: const Duration(minutes: 12),
        );
        if (result.exitCode == 0) {
          final version =
              _extractPythonVersion('${result.stdout}\n${result.stderr}') ??
              latest;
          onProgress?.call('Python 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Python 已通过 pyenv 更新到 $version',
            newVersion: version,
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'pyenv 更新失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.homebrew:
        final formula = context.brewFormula ?? 'python';
        final targetVersion = await _queryLatestHomebrewVersion(formula);
        onProgress?.call('使用 Homebrew 更新 Python…');
        final result = await _runWithProgress(
          'brew',
          ['upgrade', formula],
          onProgress: onProgress,
          timeout: const Duration(minutes: 8),
        );
        if (result.exitCode == 0) {
          final version =
              await _readPythonVersion(context.executablePath) ?? targetVersion;
          onProgress?.call(
            version == null ? 'Python 更新完成' : 'Python 已更新到 $version',
          );
          return PluginOperationResult(
            success: true,
            message: version == null
                ? 'Python 已通过 Homebrew 更新'
                : 'Python 已通过 Homebrew 更新到 $version',
            newVersion: version,
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'Homebrew 更新 Python 失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.system:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 来自系统环境，暂不支持自动升级，请手动维护。',
        );
      case _PythonRuntimeSource.unknown:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 安装来源未知，暂不支持自动升级，请手动维护。',
        );
    }
  }

  Future<PluginOperationResult> updatePip({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 运行时…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时。',
      );
    }

    switch (context.source) {
      case _PythonRuntimeSource.pyenv:
        onProgress?.call('正在升级 pip…');
        final result = await _runBoundPythonCommand(
          context.executablePath,
          ['-m', 'pip', 'install', '--upgrade', 'pip'],
          onProgress: onProgress,
          timeout: const Duration(minutes: 8),
        );
        if (result.exitCode != 0) {
          final updateMessage = result.stderr.isNotEmpty
              ? result.stderr
              : result.stdout;
          if (_isExternallyManagedPipError(updateMessage)) {
            return PluginOperationResult(
              success: false,
              message: _pipManagedEnvironmentMessage(context),
            );
          }
          return PluginOperationResult(
            success: false,
            message: 'pip 升级失败: $updateMessage',
          );
        }
        final version = await _readPipVersion(context.executablePath);
        if (version == null) {
          return const PluginOperationResult(
            success: false,
            message: 'pip 升级后验证失败',
          );
        }
        onProgress?.call('pip 已更新到 $version');
        return PluginOperationResult(
          success: true,
          message: 'pip 已更新到 $version',
          newVersion: version,
        );
      case _PythonRuntimeSource.homebrew:
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
      case _PythonRuntimeSource.system:
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
      case _PythonRuntimeSource.unknown:
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
    }
  }

  Future<PluginOperationResult> updatePlaywright({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在更新 Playwright…');
    final result = await _runWithProgress(
      'npm',
      ['update', '-g', 'playwright'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 5),
    );
    if (result.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: '更新失败: ${result.stderr}',
      );
    }
    onProgress?.call('正在更新 Playwright 浏览器…');
    await _runWithProgress(
      'npx',
      ['playwright', 'install'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 10),
    );
    final verify = await runTrackedProcessOrFailed('npx', [
      'playwright',
      '--version',
    ], timeout: const Duration(seconds: 15));
    if (verify.exitCode == 0) {
      final version = verify.stdout.toString().trim().replaceFirst(
        RegExp(r'^Version\s+', caseSensitive: false),
        '',
      );
      return PluginOperationResult(
        success: true,
        message: 'Playwright 已更新到 $version',
        newVersion: version,
      );
    }
    return const PluginOperationResult(
      success: false,
      message: 'Playwright 更新后验证失败',
    );
  }

  Future<PluginOperationResult> uninstallNodeJs({
    required bool playwrightInstalled,
    void Function(String line)? onProgress,
  }) async {
    if (playwrightInstalled) {
      return const PluginOperationResult(
        success: false,
        message: 'Playwright 依赖 Node.js，请先卸载 Playwright',
      );
    }
    onProgress?.call('正在卸载 Node.js…');
    final brewCheck = await runTrackedProcessOrFailed('which', [
      'brew',
    ], timeout: const Duration(seconds: 5));
    if (brewCheck.exitCode == 0) {
      final result = await _runWithProgress('brew', [
        'uninstall',
        'node',
      ], onProgress: onProgress);
      if (result.exitCode == 0) {
        onProgress?.call('Node.js 已卸载');
        return const PluginOperationResult(
          success: true,
          message: 'Node.js 已通过 Homebrew 卸载',
        );
      }
      return PluginOperationResult(
        success: false,
        message: '卸载失败: ${result.stderr}',
      );
    }
    return const PluginOperationResult(
      success: false,
      message: '未找到可用的包管理器来卸载 Node.js，请手动卸载',
    );
  }

  Future<PluginOperationResult> uninstallPython({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 安装方式…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时。',
      );
    }

    switch (context.source) {
      case _PythonRuntimeSource.pyenv:
        final version = context.pyenvVersion ?? context.version;
        if (version == null) {
          return const PluginOperationResult(
            success: false,
            message: '无法识别当前 pyenv Python 版本。',
          );
        }
        onProgress?.call('使用 pyenv 卸载 Python $version…');
        final script = StringBuffer()..writeln('pyenv uninstall -f $version');
        final remaining = await _remainingPyenvVersions(excluding: version);
        if (remaining.isNotEmpty) {
          remaining.sort(_compareSemver);
          script.writeln('pyenv global ${remaining.last}');
        } else {
          script.writeln('pyenv global system');
        }
        final result = await _runPythonShellCommand(
          script.toString(),
          onProgress: onProgress,
          timeout: const Duration(minutes: 8),
        );
        if (result.exitCode == 0) {
          onProgress?.call('Python $version 已卸载');
          return PluginOperationResult(
            success: true,
            message: 'Python $version 已通过 pyenv 卸载',
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'pyenv 卸载失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.homebrew:
        final formula = context.brewFormula ?? 'python';
        onProgress?.call('使用 Homebrew 卸载 Python…');
        final result = await _runWithProgress(
          'brew',
          ['uninstall', formula],
          onProgress: onProgress,
          timeout: const Duration(minutes: 8),
        );
        if (result.exitCode == 0) {
          onProgress?.call('Python 已卸载');
          return const PluginOperationResult(
            success: true,
            message: 'Python 已通过 Homebrew 卸载',
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'Homebrew 卸载 Python 失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.system:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 来自系统环境，暂不支持自动卸载。',
        );
      case _PythonRuntimeSource.unknown:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 安装来源未知，暂不支持自动卸载。',
        );
    }
  }

  Future<PluginOperationResult> uninstallPip({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('pip 不支持独立卸载');
    return const PluginOperationResult(
      success: false,
      message: 'pip 不支持卸载，仅支持安装与升级。',
    );
  }

  Future<PluginOperationResult> uninstallPlaywright({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在卸载 Playwright…');
    final result = await _runWithProgress('npm', [
      'uninstall',
      '-g',
      'playwright',
    ], onProgress: onProgress);
    if (result.exitCode == 0) {
      onProgress?.call('Playwright 已卸载');
      return const PluginOperationResult(
        success: true,
        message: 'Playwright 已卸载',
      );
    }
    return PluginOperationResult(
      success: false,
      message: '卸载失败: ${result.stderr}',
    );
  }

  Future<List<String>> _remainingPyenvVersions({
    required String excluding,
  }) async {
    final result = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}pyenv versions --bare'],
      timeout: const Duration(seconds: 8),
      tag: 'plugin_lifecycle.pyenv_versions',
    );
    if (result.exitCode != 0) return const [];
    final versions = <String>[];
    for (final line in result.stdout.toString().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed == excluding) continue;
      if (_isSemanticVersion(trimmed)) versions.add(trimmed);
    }
    return versions;
  }

  Future<_SimpleProcessResult> _runWithProgress(
    String executable,
    List<String> arguments, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 3),
    Map<String, String>? environment,
  }) async {
    try {
      final mergedEnv = <String, String>{
        ...?environment,
        ..._proxyEnv(),
      };
      final process = await startTrackedProcess(
        executable,
        arguments,
        environment: mergedEnv,
      );
      final stdoutLines = <String>[];
      final stderrLines = <String>[];
      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) {
            stdoutLines.add(line);
            onProgress?.call(line.trim());
          }
        }
      });
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) {
            stderrLines.add(line);
            onProgress?.call(line.trim());
          }
        }
      });
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      return _SimpleProcessResult(
        exitCode: exitCode,
        stdout: stdoutLines.join('\n'),
        stderr: stderrLines.join('\n'),
      );
    } catch (e) {
      return _SimpleProcessResult(exitCode: -1, stdout: '', stderr: '$e');
    }
  }
}

class _SimpleProcessResult {
  const _SimpleProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

enum _PythonRuntimeSource { pyenv, homebrew, system, unknown }

class _PythonRuntimeContext {
  const _PythonRuntimeContext({
    required this.source,
    required this.executablePath,
    this.version,
    this.pyenvVersion,
    this.brewFormula,
  });

  final _PythonRuntimeSource source;
  final String executablePath;
  final String? version;
  final String? pyenvVersion;
  final String? brewFormula;
}

bool _isSemanticVersion(String value) {
  return RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value);
}

int _compareSemver(String a, String b) {
  final ap = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final bp = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  for (int i = 0; i < 3; i++) {
    final av = i < ap.length ? ap[i] : 0;
    final bv = i < bp.length ? bp[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

String? _extractPythonVersion(String output) {
  final match = RegExp(r'Python\s+(\d+\.\d+\.\d+)').firstMatch(output);
  return match?.group(1);
}

String? _extractPipVersion(String output) {
  final match = RegExp(r'pip\s+(\d+(?:\.\d+)+)').firstMatch(output);
  return match?.group(1);
}

String? _extractFirstSemver(String output, {String? prefix}) {
  final matches = RegExp(r'(\d+\.\d+\.\d+)').allMatches(output);
  for (final match in matches) {
    final value = match.group(1);
    if (value == null) continue;
    if (prefix == null || value.startsWith(prefix)) return value;
  }
  return null;
}

List<String> _extractStablePyenvVersions(String output, {String? prefix}) {
  final versions = <String>{};
  for (final match in RegExp(r'^\s*(\d+\.\d+\.\d+)\s*$').allMatches(output)) {
    final value = match.group(1);
    if (value == null) continue;
    if (prefix != null && !value.startsWith(prefix)) continue;
    versions.add(value);
  }
  return versions.toList(growable: false);
}

String? _extractPyenvVersionFromPath(String path) {
  final match = RegExp(r'/.pyenv/versions/([^/]+)/').firstMatch(path);
  final value = match?.group(1);
  if (value != null && _isSemanticVersion(value)) return value;
  return null;
}

bool _looksLikeHomebrewPath(String path) {
  return path.contains('/Cellar/python') ||
      path.contains('/Homebrew/Cellar/python') ||
      path.contains('/opt/homebrew/') ||
      path.contains('/usr/local/opt/python') ||
      path.contains('/usr/local/bin/python');
}

bool _looksLikeSystemPython(String path) {
  return path.startsWith('/usr/bin/') ||
      path.startsWith('/Library/Developer/CommandLineTools/');
}

String? _extractBrewPythonFormulaFromPath(String path) {
  final matches = RegExp(r'/(python(?:@[\d.]+)?)(?:/|$)').allMatches(path);
  if (matches.isEmpty) return null;
  return matches.last.group(1);
}
