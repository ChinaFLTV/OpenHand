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

String pluginPlaywrightDataDirectory({
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
    return p.normalize(
      p.isAbsolute(configured) ? configured : p.absolute(configured),
    );
  }

  final home = (homeDirectory ?? env['HOME'] ?? env['USERPROFILE'] ?? '')
      .trim();
  if (Platform.isWindows) {
    final localAppData = env['LOCALAPPDATA']?.trim();
    if (localAppData != null && localAppData.isNotEmpty) {
      return p.join(localAppData, 'ms-playwright');
    }
    return p.join(home, 'AppData', 'Local', 'ms-playwright');
  }
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
