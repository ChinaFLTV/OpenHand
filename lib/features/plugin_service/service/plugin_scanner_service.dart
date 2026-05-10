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

  /// 通过交互式登录 shell 执行命令，确保 nvm/fnm/volta 等正确加载。
  Future<ProcessResult> _shellRun(String command) {
    return Process.run(
      _pickShell(),
      ['-ic', command],
    ).timeout(const Duration(seconds: 12));
  }

  /// 扫描 NodeJS 安装状态。
  Future<PluginInfo> scanNodeJs() async {
    try {
      final versionResult = await _shellRun('node --version');
      if (versionResult.exitCode == 0) {
        final version = versionResult.stdout.toString().trim();
        final pathResult = await _shellRun('which node');
        final installPath = pathResult.exitCode == 0
            ? pathResult.stdout.toString().trim()
            : null;
        // 检查最新版本（通过 npm view node version，可能失败）
        String? latestVersion;
        try {
          final latestResult = await _shellRun('npm view node version');
          if (latestResult.exitCode == 0) {
            latestVersion = 'v${latestResult.stdout.toString().trim()}';
          }
        } catch (_) {
          // 网络不可用时忽略
        }
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
