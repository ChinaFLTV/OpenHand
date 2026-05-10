import 'dart:async';
import 'dart:io';

import '../../../app/support/silent_log.dart';
import '../model/plugin_info.dart';

/// 扫描本机已安装的插件（NodeJS / PlayWright），检测版本与可用性。
///
/// 通过登录 shell 执行 CLI 命令（确保 nvm/fnm 等版本管理器正确加载），
/// 检测版本号、安装路径。
class PluginScannerService {
  PluginScannerService();

  static String _pickShell() {
    final shell = Platform.environment['SHELL'];
    if (shell != null && shell.isNotEmpty) return shell;
    return '/bin/zsh';
  }

  /// 通过显式 source nvm/fnm 初始化脚本后执行命令。
  /// 不使用 -i（交互式）避免 shell 初始化噪音污染 stdout。
  Future<ProcessResult> _shellRun(String command) {
    final home = Platform.environment['HOME'] ?? '';
    // 构建一个能正确加载版本管理器的脚本
    final script = StringBuffer();
    // nvm
    script.writeln('export NVM_DIR="\${NVM_DIR:-$home/.nvm}"');
    script.writeln('[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"');
    // fnm
    script.writeln('if command -v fnm >/dev/null 2>&1; then eval "\$(fnm env)"; fi');
    // volta
    script.writeln('export VOLTA_HOME="\${VOLTA_HOME:-$home/.volta}"');
    script.writeln('export PATH="\$VOLTA_HOME/bin:\$PATH"');
    // 执行实际命令
    script.writeln(command);
    return Process.run(
      _pickShell(),
      ['-c', script.toString()],
    ).timeout(const Duration(seconds: 15));
  }

  /// 扫描 NodeJS 安装状态。
  Future<PluginInfo> scanNodeJs() async {
    try {
      final versionResult = await _shellRun('node --version');
      if (versionResult.exitCode == 0) {
        // 从输出中提取 vX.Y.Z 格式的版本号（过滤 shell 初始化噪音）
        final version = _extractVersion(versionResult.stdout.toString());
        if (version == null) {
          return const PluginInfo(
            id: 'nodejs',
            name: 'Node.js',
            description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
            status: PluginStatus.notInstalled,
            dependencies: [],
            dependents: ['playwright'],
          );
        }
        final pathResult = await _shellRun('which node');
        final rawPath = pathResult.exitCode == 0
            ? pathResult.stdout.toString().trim()
            : null;
        // 从 which 输出中提取路径（过滤可能的 shell 噪音）
        final installPath = rawPath != null
            ? rawPath.split('\n').lastWhere(
                (l) => l.trim().startsWith('/'),
                orElse: () => rawPath,
              ).trim()
            : null;
        // 检查最新版本
        String? latestVersion;
        try {
          final latestResult = await _shellRun('npm view node version');
          if (latestResult.exitCode == 0) {
            final raw = latestResult.stdout.toString().trim();
            final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(raw);
            if (match != null) {
              latestVersion = 'v${match.group(1)}';
            }
          }
        } catch (_) {}
        return PluginInfo(
          id: 'nodejs',
          name: 'Node.js',
          description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
          status: PluginStatus.installed,
          installedVersion: version,
          latestVersion: latestVersion,
          installPath: installPath,
          dependencies: const [],
          dependents: const ['playwright'],
        );
      }
    } catch (e) {
      silentLog('PluginScanner', 'scanNodeJs', e);
    }
    return const PluginInfo(
      id: 'nodejs',
      name: 'Node.js',
      description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
      status: PluginStatus.notInstalled,
      dependencies: [],
      dependents: ['playwright'],
    );
  }

  /// 从命令输出中提取 vX.Y.Z 格式的版本号。
  /// 过滤 shell 初始化时可能输出的噪音（nvm 警告、motd 等）。
  static String? _extractVersion(String output) {
    final match = RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(output);
    return match != null ? match.group(0) : null;
  }

  /// 扫描 Playwright 安装状态。
  Future<PluginInfo> scanPlaywright() async {
    try {
      // Playwright 依赖 Node.js，先检查 npx 是否可用
      final npxCheck = await _shellRun('which npx');
      if (npxCheck.exitCode != 0) {
        return const PluginInfo(
          id: 'playwright',
          name: 'Playwright',
          description: '浏览器自动化测试框架，支持 Chromium / Firefox / WebKit',
          status: PluginStatus.notInstalled,
          dependencies: ['nodejs'],
          dependents: [],
        );
      }
      final versionResult = await _shellRun('npx playwright --version');
      if (versionResult.exitCode == 0) {
        final output = versionResult.stdout.toString().trim();
        // playwright 输出格式: "Version 1.x.x" 或直接 "1.x.x"
        final version = output
            .replaceFirst(RegExp(r'^Version\s+', caseSensitive: false), '')
            .trim();
        // 检查最新版本
        String? latestVersion;
        try {
          final latestResult = await _shellRun('npm view playwright version');
          if (latestResult.exitCode == 0) {
            latestVersion = latestResult.stdout.toString().trim();
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
          dependents: const [],
        );
      }
    } catch (e) {
      silentLog('PluginScanner', 'scanPlaywright', e);
    }
    return const PluginInfo(
      id: 'playwright',
      name: 'Playwright',
      description: '浏览器自动化测试框架，支持 Chromium / Firefox / WebKit',
      status: PluginStatus.notInstalled,
      dependencies: ['nodejs'],
      dependents: [],
    );
  }

  /// 扫描所有已知插件。
  Future<List<PluginInfo>> scanAll() async {
    final results = await Future.wait([scanNodeJs(), scanPlaywright()]);
    // 更新 dependents 关系：如果 playwright 已安装，则 nodejs 的 dependents 包含它
    final nodeJs = results[0];
    final playwright = results[1];
    final updatedNodeJs = nodeJs.copyWith(
      dependents: playwright.isInstalled ? const ['playwright'] : const [],
    );
    return [updatedNodeJs, playwright];
  }
}
