import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/node_package_manifest.dart';
import '../../../shared/util/platform_environment.dart';
import '../../../shared/util/platform_shell.dart';
import '../../../shared/util/version_compare.dart';

const Duration _pluginEnvironmentProbeTimeout = Duration(milliseconds: 500);
final RegExp _pluginPyenvVersionPathPattern = RegExp(
  r'(?:^|[\\/])\.pyenv(?:[\\/]pyenv-win)?[\\/]versions[\\/]([^\\/]+)(?:[\\/]|$)',
  caseSensitive: false,
);
final RegExp _pluginBrewPythonFormulaPathPattern = RegExp(
  r'/(python(?:@[\d.]+)?)(?:/|$)',
);
final RegExp _pluginPlaywrightVersionPrefixPattern = RegExp(
  r'^Version\s+',
  caseSensitive: false,
);

String pluginShellExecutable() {
  return preferredPosixShellExecutable(requireBashCompatible: true);
}

String pluginNvmDirectoryPath() => _pluginToolchainDirectoryPath(
  environmentName: 'NVM_DIR',
  defaultDirectoryName: '.nvm',
);

String pluginPyenvRootDirectoryPath() => _pluginToolchainDirectoryPath(
  environmentName: 'PYENV_ROOT',
  defaultDirectoryName: '.pyenv',
);

String pluginVoltaHomeDirectoryPath() => _pluginToolchainDirectoryPath(
  environmentName: 'VOLTA_HOME',
  defaultDirectoryName: '.volta',
);

String _pluginToolchainDirectoryPath({
  required String environmentName,
  required String defaultDirectoryName,
}) {
  final configured =
      currentPlatformEnvironmentValue(environmentName)?.trim() ?? '';
  if (p.isAbsolute(configured)) return p.normalize(configured);
  return p.join(OpenHandPaths.homeDirectoryPath(), defaultDirectoryName);
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

String? extractPluginPyenvVersionFromPath(String path) {
  final value = _pluginPyenvVersionPathPattern.firstMatch(path)?.group(1);
  return value != null && isStrictSemanticVersionText(value) ? value : null;
}

String? extractPluginBrewPythonFormulaFromPath(String path) {
  final matches = _pluginBrewPythonFormulaPathPattern.allMatches(path);
  return matches.isEmpty ? null : matches.last.group(1);
}

String normalizePluginPlaywrightVersion(Object? output) {
  return '$output'
      .trim()
      .replaceFirst(_pluginPlaywrightVersionPrefixPattern, '')
      .trim();
}

String? extractPluginHomebrewStableVersion(Object? decoded) {
  final formulae = decoded is Map ? decoded['formulae'] : null;
  if (formulae is! List || formulae.isEmpty) return null;
  final formula = formulae.first;
  if (formula is! Map) return null;
  final versions = formula['versions'];
  if (versions is! Map) return null;
  final value = versions['stable'];
  if (value is! String) return null;
  final stable = value.trim();
  return stable.isEmpty ? null : stable;
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

/// 从独占一行的稳定版本号中取最大版本，跳过预览版和不匹配的前缀。
String? extractPluginLatestStableVersion(String output, {String? prefix}) {
  String? latest;
  for (final match in _pluginStableVersionLinePattern.allMatches(output)) {
    final value = match.group(1)!;
    if (prefix != null && !value.startsWith(prefix)) continue;
    if (latest == null || compareSemanticVersions(value, latest) > 0) {
      latest = value;
    }
  }
  return latest;
}

String? extractPluginAbsolutePath(String output) {
  for (final line in output.split('\n').reversed) {
    final path = line.trim();
    if (p.isAbsolute(path)) return p.normalize(path);
  }
  return null;
}

/// 由 `npm root -g` 的执行结果定位全局包安装位置。
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
  final configured = platformEnvironmentValue(
    env,
    'PLAYWRIGHT_BROWSERS_PATH',
  )?.trim();
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

  final home =
      (homeDirectory ??
              platformEnvironmentValue(env, 'HOME') ??
              platformEnvironmentValue(env, 'USERPROFILE') ??
              '')
          .trim();
  if (Platform.isWindows) {
    final localAppData = platformEnvironmentValue(env, 'LOCALAPPDATA')?.trim();
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

Future<bool> pluginPyenvInstallationExists({String? homeDirectory}) async {
  final root = homeDirectory == null
      ? pluginPyenvRootDirectoryPath()
      : p.join(homeDirectory.trim(), '.pyenv');
  if (!p.isAbsolute(root)) return false;
  final candidates = <String>{
    p.join(root, 'bin', 'pyenv'),
    p.join(root, 'bin', 'pyenv.bat'),
    p.join(root, 'bin', 'pyenv.exe'),
    p.join(root, 'pyenv-win', 'bin', 'pyenv.bat'),
    p.join(root, 'pyenv-win', 'bin', 'pyenv.exe'),
  };
  for (final candidate in candidates) {
    if (await isRegularFilePath(
      candidate,
      timeout: _pluginEnvironmentProbeTimeout,
      followLinks: true,
    )) {
      return true;
    }
  }
  return false;
}

Future<bool> pluginDockerDesktopInstallationExists({
  bool? isMacOS,
  String? systemApplicationsDirectory,
  String? homeDirectory,
}) async {
  if (!(isMacOS ?? Platform.isMacOS)) return false;
  final systemApplications = (systemApplicationsDirectory ?? '/Applications')
      .trim();
  final home = (homeDirectory ?? OpenHandPaths.homeDirectoryPath()).trim();
  final candidates = <String>{
    if (p.isAbsolute(systemApplications))
      p.join(systemApplications, 'Docker.app'),
    if (p.isAbsolute(home)) p.join(home, 'Applications', 'Docker.app'),
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
