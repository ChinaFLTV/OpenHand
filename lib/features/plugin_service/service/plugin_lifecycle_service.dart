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

  /// 安装 NodeJS（通过 brew / fnm）。
  Future<PluginOperationResult> installNodeJs({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测包管理器…');
    // 优先尝试 brew
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
    // 无 brew 时尝试 fnm
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
    }
    return const PluginOperationResult(
      success: false,
      message: '未找到可用的包管理器 (brew / fnm)。请手动安装 Node.js: https://nodejs.org',
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
  Future<PluginOperationResult> updateNodeJs({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在更新 Node.js…');
    final brewCheck = await Process.run('which', ['brew'])
        .timeout(const Duration(seconds: 5));
    if (brewCheck.exitCode == 0) {
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
            message: 'Node.js 已更新到 $version',
            newVersion: version,
          );
        }
      }
      return PluginOperationResult(
        success: false,
        message: '更新失败: ${result.stderr}',
      );
    }
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
      message: '未找到可用的包管理器来更新 Node.js',
    );
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
        timeout: const Duration(minutes: 3),
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
      timeout: const Duration(minutes: 3),
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
            onProgress?.call('[stderr] ${line.trim()}');
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
