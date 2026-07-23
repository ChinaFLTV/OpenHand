import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/system_proxy.dart';
import '../../../shared/util/bounded_file_io.dart';

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
