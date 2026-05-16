import 'dart:async';
import 'dart:io';

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
/// - 更新时按依赖顺序执行
class PluginLifecycleService {
  PluginLifecycleService();

  /// nvm 是 shell 函数而非可执行文件，需要先 source 初始化脚本。
  /// 此方法构建一个能正确加载 nvm 的 shell 命令前缀。
  static String _nvmSourcePrefix() {
    final home = Platform.environment['HOME'] ?? '';
    // nvm 常见安装位置
    return '''
export NVM_DIR="\${NVM_DIR:-$home/.nvm}"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
''';
  }

  /// 通过正确 source nvm 后执行 nvm 命令。
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
    );
  }

  /// 检测 nvm 是否可用。
  Future<bool> _isNvmAvailable() async {
    final home = Platform.environment['HOME'] ?? '';
    final nvmSh = File('$home/.nvm/nvm.sh');
    return nvmSh.existsSync();
  }

  /// 安装 NodeJS（通过 nvm / fnm / brew）。
  /// 优先使用已存在的版本管理器，其次 brew。
  Future<PluginOperationResult> installNodeJs({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测可用的包管理器…');

    // 优先 nvm（最常见的 Node 版本管理器）
    if (await _isNvmAvailable()) {
      onProgress?.call('使用 nvm 安装 Node.js…');
      final result = await _runNvmCommand(
        'nvm install node && nvm alias default node && node --version',
        onProgress: onProgress,
      );
      if (result.exitCode == 0) {
        final lines = result.stdout.split('\n')
            .map((l) => l.trim())
            .where((l) => l.startsWith('v') && RegExp(r'^v\d+\.\d+').hasMatch(l))
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

    // 其次 fnm
    final fnmCheck = await Process.run('which', ['fnm'])
        .timeout(const Duration(seconds: 5));
    if (fnmCheck.exitCode == 0) {
      onProgress?.call('使用 fnm 安装 Node.js LTS…');
      final result = await _runWithProgress(
        'fnm',
        ['install', '--lts'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        await Process.run('fnm', ['default', 'lts-latest'])
            .timeout(const Duration(seconds: 10));
        final verify = await Process.run('node', ['--version'])
            .timeout(const Duration(seconds: 8));
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

    // 最后 brew
    final brewCheck = await Process.run('which', ['brew'])
        .timeout(const Duration(seconds: 5));
    if (brewCheck.exitCode == 0) {
      onProgress?.call('使用 Homebrew 安装 Node.js…');
      final result = await _runWithProgress(
        'brew',
        ['install', 'node'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        final verify = await Process.run('node', ['--version'])
            .timeout(const Duration(seconds: 8));
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
      message: '未找到可用的包管理器 (nvm / fnm / brew)。请手动安装 Node.js: https://nodejs.org',
    );
  }

  /// 安装 Playwright（全局 npm 包 + 浏览器）。
  Future<PluginOperationResult> installPlaywright({
    void Function(String line)? onProgress,
  }) async {
    // 前置检查：NodeJS 必须已安装
    final nodeCheck = await Process.run('node', ['--version'])
        .timeout(const Duration(seconds: 8));
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
    // 安装浏览器
    onProgress?.call('正在安装 Playwright 浏览器…');
    await _runWithProgress(
      'npx',
      ['playwright', 'install'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 10),
    );
    // 验证
    final verify = await Process.run('npx', ['playwright', '--version'])
        .timeout(const Duration(seconds: 15));
    if (verify.exitCode == 0) {
      final version = verify.stdout
          .toString()
          .trim()
          .replaceFirst(RegExp(r'^Version\s+', caseSensitive: false), '');
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

  /// 更新 NodeJS。
  /// 根据当前 Node 的安装路径自动判断使用哪个包管理器更新。
  Future<PluginOperationResult> updateNodeJs({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Node.js 安装方式…');
    // 先获取当前 node 路径，判断安装来源
    final whichResult = await Process.run('which', ['node'])
        .timeout(const Duration(seconds: 5));
    final nodePath = whichResult.exitCode == 0
        ? whichResult.stdout.toString().trim()
        : '';

    // 判断安装来源
    final isNvm = nodePath.contains('.nvm/');
    final isFnm = nodePath.contains('.fnm/') || nodePath.contains('/fnm/');
    final isVolta = nodePath.contains('.volta/');
    final isBrew = nodePath.contains('/homebrew/') ||
        nodePath.contains('/Cellar/') ||
        nodePath.startsWith('/opt/homebrew/') ||
        nodePath.startsWith('/usr/local/bin/');

    // 优先使用检测到的安装方式
    if (isNvm) {
      onProgress?.call('检测到 nvm 管理的 Node.js，使用 nvm 更新…');
      // 使用 nvm install node 安装最新 current 版本（与扫描器报告的 latestVersion 一致），
      // 并在同一 shell 会话中获取新版本号（避免跨进程 default alias 未生效的问题）。
      final result = await _runNvmCommand(
        'nvm install node --reinstall-packages-from=current && nvm alias default node && node --version',
        onProgress: onProgress,
      );
      if (result.exitCode == 0) {
        // 从 stdout 最后一行提取版本号（node --version 的输出）
        final lines = result.stdout.split('\n')
            .map((l) => l.trim())
            .where((l) => l.startsWith('v') && RegExp(r'^v\d+\.\d+').hasMatch(l))
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
        // 版本号提取失败但命令成功，仍视为成功
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
        await Process.run('fnm', ['default', 'lts-latest'])
            .timeout(const Duration(seconds: 10));
        final verify = await Process.run('node', ['--version'])
            .timeout(const Duration(seconds: 8));
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
        final verify = await Process.run('node', ['--version'])
            .timeout(const Duration(seconds: 8));
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
        final verify = await Process.run('node', ['--version'])
            .timeout(const Duration(seconds: 8));
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

    // 兜底：尝试 fnm → brew 顺序
    onProgress?.call('未能确定安装方式，尝试可用的包管理器…');
    final fnmCheck = await Process.run('which', ['fnm'])
        .timeout(const Duration(seconds: 5));
    if (fnmCheck.exitCode == 0) {
      final result = await _runWithProgress(
        'fnm',
        ['install', '--lts'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        await Process.run('fnm', ['default', 'lts-latest'])
            .timeout(const Duration(seconds: 10));
        final verify = await Process.run('node', ['--version'])
            .timeout(const Duration(seconds: 8));
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
      message: '未找到可用的包管理器来更新 Node.js。\n'
          '请根据您的安装方式手动更新：\n'
          '  · nvm: nvm install --lts\n'
          '  · fnm: fnm install --lts\n'
          '  · brew: brew upgrade node\n'
          '  · volta: volta install node@latest',
    );
  }

  static String _pickShell() {
    final shell = Platform.environment['SHELL'];
    if (shell != null && shell.isNotEmpty) return shell;
    return '/bin/zsh';
  }

  /// 更新 Playwright。
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
    // 更新浏览器
    onProgress?.call('正在更新 Playwright 浏览器…');
    await _runWithProgress(
      'npx',
      ['playwright', 'install'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 10),
    );
    final verify = await Process.run('npx', ['playwright', '--version'])
        .timeout(const Duration(seconds: 15));
    if (verify.exitCode == 0) {
      final version = verify.stdout
          .toString()
          .trim()
          .replaceFirst(RegExp(r'^Version\s+', caseSensitive: false), '');
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

  /// 卸载 NodeJS。
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
    final brewCheck = await Process.run('which', ['brew'])
        .timeout(const Duration(seconds: 5));
    if (brewCheck.exitCode == 0) {
      final result = await _runWithProgress(
        'brew',
        ['uninstall', 'node'],
        onProgress: onProgress,
      );
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

  /// 卸载 Playwright。
  Future<PluginOperationResult> uninstallPlaywright({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在卸载 Playwright…');
    final result = await _runWithProgress(
      'npm',
      ['uninstall', '-g', 'playwright'],
      onProgress: onProgress,
    );
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

  Future<_SimpleProcessResult> _runWithProgress(
    String executable,
    List<String> arguments, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    try {
      final process = await Process.start(executable, arguments);
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
            // 不加 [stderr] 前缀：curl/wget/nvm 等工具的进度条正常输出到 stderr，
            // 这是 Unix 惯例（stdout 留给数据，stderr 用于状态/进度），不代表错误。
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
      return _SimpleProcessResult(
        exitCode: -1,
        stdout: '',
        stderr: '$e',
      );
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
