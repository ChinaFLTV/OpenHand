import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/system_proxy.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/node_package_manifest.dart';

const Duration _pluginEnvironmentProbeTimeout = Duration(milliseconds: 500);

String pluginShellExecutable() {
  final shell = Platform.environment['SHELL'];
  if (shell != null && shell.isNotEmpty) return shell;
  return '/bin/zsh';
}

Map<String, String> pluginProxyEnvironment() {
  return SystemProxyResolver.instance.resolveSubprocessEnvironment();
}

bool pluginLooksLikeHomebrewPythonPath(String path) {
  return path.contains('/Cellar/python') ||
      path.contains('/Homebrew/Cellar/python') ||
      path.contains('/opt/homebrew/') ||
      path.contains('/usr/local/opt/python') ||
      path.contains('/usr/local/bin/python');
}

bool pluginLooksLikeSystemPythonPath(String path) {
  return path.startsWith('/usr/bin/') ||
      path.startsWith('/Library/Developer/CommandLineTools/');
}

final class PluginNpmPackageInstallation {
  const PluginNpmPackageInstallation({
    required this.packageDirectory,
    required this.executablePath,
  });

  final String packageDirectory;
  final String executablePath;
}

/// 版本号在任意文本里的出现（不锚定行首行尾）。
final RegExp _pluginSemverPattern = RegExp(r'(\d+\.\d+\.\d+)');

/// 独占一行的稳定版本号；`pyenv install --list` 里带后缀的预览版因此被排除。
///
/// **必须开 multiLine**：不开时 `^`/`$` 只锚定整段输入的首尾，对多行输出永远
/// 匹配不到——两个插件服务里的旧副本都漏了这个标记，导致「查最新 Python 版本」
/// 的兜底分支实际上从来没生效过。
final RegExp _pluginStableVersionLinePattern = RegExp(
  r'^\s*(\d+\.\d+\.\d+)\s*$',
  multiLine: true,
);

/// 取输出里第一个（可按 [prefix] 过滤的）版本号。
String? extractPluginFirstSemver(String output, {String? prefix}) {
  for (final match in _pluginSemverPattern.allMatches(output)) {
    final value = match.group(1);
    if (value == null) continue;
    if (prefix == null || value.startsWith(prefix)) return value;
  }
  return null;
}

/// 取输出里所有独占一行的稳定版本号，按 [prefix] 过滤后去重。
List<String> extractPluginStableVersionLines(String output, {String? prefix}) {
  final versions = <String>{};
  for (final match in _pluginStableVersionLinePattern.allMatches(output)) {
    final value = match.group(1);
    if (value == null) continue;
    if (prefix != null && !value.startsWith(prefix)) continue;
    versions.add(value);
  }
  return versions.toList(growable: false);
}

String? extractPluginAbsolutePath(String output) {
  for (final line in output.split('\n').reversed) {
    final path = line.trim();
    if (p.isAbsolute(path)) return p.normalize(path);
  }
  return null;
}

/// 由 `npm root -g` 的执行结果定位全局包安装位置。
///
/// 两个插件服务跑这条命令的方式不同（一个走托管进程、一个走 shell），但拿到
/// 输出之后的解析完全一样，此前各写一遍。
Future<PluginNpmPackageInstallation?> resolvePluginGlobalNpmPackage({
  required int exitCode,
  required String stdout,
  required String packageName,
}) async {
  if (exitCode != 0) return null;
  final globalRoot = extractPluginAbsolutePath(stdout);
  if (globalRoot == null) return null;
  return resolvePluginNpmPackageInstallation(
    globalRoot: globalRoot,
    packageName: packageName,
  );
}

Future<PluginNpmPackageInstallation?> resolvePluginNpmPackageInstallation({
  required String globalRoot,
  required String packageName,
}) async {
  final root = p.normalize(globalRoot.trim());
  final segments = packageName
      .trim()
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (!p.isAbsolute(root) ||
      segments.isEmpty ||
      segments.any((segment) => segment == '.' || segment == '..')) {
    return null;
  }
  final packageDirectory = p.normalize(p.joinAll(<String>[root, ...segments]));
  if (!p.isWithin(root, packageDirectory)) return null;
  final executablePath = await resolveNodePackageBinEntry(packageDirectory);
  if (executablePath == null) return null;
  return PluginNpmPackageInstallation(
    packageDirectory: packageDirectory,
    executablePath: executablePath,
  );
}

String? pluginPlaywrightDataDirectory({
  required String packageDirectory,
  Map<String, String>? environment,
  String? homeDirectory,
}) {
  final env = environment ?? Platform.environment;
  final configured = env['PLAYWRIGHT_BROWSERS_PATH']?.trim();
  if (configured == '0') {
    return p.join(
      packageDirectory,
      'node_modules',
      'playwright-core',
      '.local-browsers',
    );
  }
  if (configured != null && configured.isNotEmpty) {
    return p.isAbsolute(configured) ? p.normalize(configured) : null;
  }

  final home = (homeDirectory ?? env['HOME'] ?? env['USERPROFILE'] ?? '')
      .trim();
  if (Platform.isWindows) {
    final localAppData = env['LOCALAPPDATA']?.trim();
    if (localAppData != null && p.isAbsolute(localAppData)) {
      return p.join(localAppData, 'ms-playwright');
    }
    return p.isAbsolute(home)
        ? p.join(home, 'AppData', 'Local', 'ms-playwright')
        : null;
  }
  if (!p.isAbsolute(home)) return null;
  if (Platform.isMacOS) {
    return p.join(home, 'Library', 'Caches', 'ms-playwright');
  }
  return p.join(home, '.cache', 'ms-playwright');
}

Future<bool> pluginPyenvInstallationExists({String? homeDirectory}) {
  final home = (homeDirectory ?? Platform.environment['HOME'] ?? '').trim();
  if (home.isEmpty) return Future<bool>.value(false);
  return isRegularFilePath(
    p.join(home, '.pyenv', 'bin', 'pyenv'),
    timeout: _pluginEnvironmentProbeTimeout,
    followLinks: true,
  );
}

Future<bool> pluginDockerDesktopInstallationExists({
  bool? isMacOS,
  String? systemApplicationsDirectory,
  String? homeDirectory,
}) async {
  if (!(isMacOS ?? Platform.isMacOS)) return false;
  final systemApplications = (systemApplicationsDirectory ?? '/Applications')
      .trim();
  final home = (homeDirectory ?? Platform.environment['HOME'] ?? '').trim();
  final candidates = <String>{
    if (systemApplications.isNotEmpty) p.join(systemApplications, 'Docker.app'),
    if (home.isNotEmpty) p.join(home, 'Applications', 'Docker.app'),
  };
  for (final candidate in candidates) {
    if (await isDirectoryPath(
      candidate,
      timeout: _pluginEnvironmentProbeTimeout,
      followLinks: true,
    )) {
      return true;
    }
  }
  return false;
}
