import 'dart:async';
import 'dart:io';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../model/plugin_info.dart';

/// 扫描本机已安装的插件（NodeJS / PlayWright），检测版本与可用性。
///
/// 对于 nvm 用户，直接读取 nvm 目录结构解析版本（不依赖 shell 环境），
/// 彻底避免 GUI 应用进程 PATH 与终端不一致的问题。
class PluginScannerService {
  PluginScannerService();

  static String _pickShell() {
    final shell = Platform.environment['SHELL'];
    if (shell != null && shell.isNotEmpty) return shell;
    return '/bin/zsh';
  }

  /// 通过 shell 执行命令（用于 fnm/volta/brew 等非 nvm 场景）。
  Future<ProcessResult> _shellRun(String command) {
    final home = Platform.environment['HOME'] ?? '';
    final script = StringBuffer();
    script.writeln('export NVM_DIR="\${NVM_DIR:-$home/.nvm}"');
    script.writeln('[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"');
    script.writeln(
      'if command -v fnm >/dev/null 2>&1; then eval "\$(fnm env)"; fi',
    );
    script.writeln('export VOLTA_HOME="\${VOLTA_HOME:-$home/.volta}"');
    script.writeln('export PATH="\$VOLTA_HOME/bin:\$PATH"');
    script.writeln(command);
    return runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', script.toString()],
      timeout: const Duration(seconds: 15),
      tag: 'plugin_scanner.shell_probe',
    );
  }

  /// 直接从 nvm 目录结构解析当前默认 Node 版本（不依赖 shell）。
  Future<({String version, String nodeBin, String npmBin})?>
  _resolveNvmDirect() async {
    final home = Platform.environment['HOME'] ?? '';
    final nvmDir = Platform.environment['NVM_DIR'] ?? '$home/.nvm';
    final versionsDir = Directory('$nvmDir/versions/node');
    if (!versionsDir.existsSync()) return null;

    // 列出所有已安装版本
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
    versions.sort(_compareVersions);

    // 读取 default alias
    String alias = 'node';
    try {
      final aliasFile = File('$nvmDir/alias/default');
      if (aliasFile.existsSync()) {
        alias = aliasFile.readAsStringSync().trim();
      }
    } catch (_) {}

    // 解析 alias → 实际版本目录
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

  static int _compareVersions(String a, String b) {
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

  /// 扫描 NodeJS 安装状态。
  Future<PluginInfo> scanNodeJs() async {
    try {
      // 方案 1：直接从 nvm 目录解析（最可靠）
      final nvm = await _resolveNvmDirect();
      if (nvm != null) {
        final versionResult = await runTrackedProcessOrFailed(nvm.nodeBin, [
          '--version',
        ], timeout: const Duration(seconds: 5));
        final version = versionResult.exitCode == 0
            ? versionResult.stdout.toString().trim()
            : nvm.version;
        String? latestVersion;
        try {
          if (File(nvm.npmBin).existsSync()) {
            final r = await runTrackedProcessOrFailed(nvm.npmBin, [
              'view',
              'node',
              'version',
            ], timeout: const Duration(seconds: 10));
            if (r.exitCode == 0) {
              final m = RegExp(
                r'(\d+\.\d+\.\d+)',
              ).firstMatch(r.stdout.toString());
              if (m != null) latestVersion = 'v${m.group(1)}';
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
          installPath: nvm.nodeBin,
          dependents: const ['playwright'],
        );
      }

      // 方案 2：通过 shell 执行（fnm / volta / brew）
      final versionResult = await _shellRun('node --version');
      if (versionResult.exitCode == 0) {
        final version = _extractVersion(versionResult.stdout.toString());
        if (version == null) {
          return _nodeNotInstalled;
        }
        final pathResult = await _shellRun('which node');
        final installPath = pathResult.exitCode == 0
            ? pathResult.stdout
                  .toString()
                  .split('\n')
                  .lastWhere((l) => l.trim().startsWith('/'), orElse: () => '')
                  .trim()
            : null;
        String? latestVersion;
        try {
          final r = await _shellRun('npm view node version');
          if (r.exitCode == 0) {
            final m = RegExp(
              r'(\d+\.\d+\.\d+)',
            ).firstMatch(r.stdout.toString());
            if (m != null) latestVersion = 'v${m.group(1)}';
          }
        } catch (_) {}
        return PluginInfo(
          id: 'nodejs',
          name: 'Node.js',
          description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
          status: PluginStatus.installed,
          installedVersion: version,
          latestVersion: latestVersion,
          installPath: installPath?.isEmpty == true ? null : installPath,
          dependents: const ['playwright'],
        );
      }
    } catch (e) {
      silentLog('PluginScanner', 'scanNodeJs', e);
    }
    return _nodeNotInstalled;
  }

  static const _nodeNotInstalled = PluginInfo(
    id: 'nodejs',
    name: 'Node.js',
    description: 'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链',
    status: PluginStatus.notInstalled,
    dependents: ['playwright'],
  );

  static String? _extractVersion(String output) {
    final match = RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(output);
    return match?.group(0);
  }

  /// 扫描 Playwright 安装状态。
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

  static const _playwrightNotInstalled = PluginInfo(
    id: 'playwright',
    name: 'Playwright',
    description: '浏览器自动化测试框架，支持 Chromium / Firefox / WebKit',
    status: PluginStatus.notInstalled,
    dependencies: ['nodejs'],
  );

  /// 扫描所有已知插件。
  Future<List<PluginInfo>> scanAll() async {
    final results = await Future.wait([scanNodeJs(), scanPlaywright()]);
    final nodeJs = results[0];
    final playwright = results[1];
    final updatedNodeJs = nodeJs.copyWith(
      dependents: playwright.isInstalled ? const ['playwright'] : const [],
    );
    return [updatedNodeJs, playwright];
  }
}
