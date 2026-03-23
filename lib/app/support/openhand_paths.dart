import 'dart:io';

import 'package:path/path.dart' as p;

abstract final class OpenHandPaths {
  static const String defaultSkillsDirectoryLabel = '~/.openhand/skills';
  static const String defaultSettingsFileLabel =
      '~/.openhand/settings/SETTINGS.toml';
  static const String defaultMcpServersFileLabel =
      '~/.openhand/mcp/mcp_servers.json';
  static const String defaultSessionsDirectoryLabel = '~/.openhand/sessions';

  static String homeDirectoryPath() {
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return _normalizeHomePath(home);
    }

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return _normalizeHomePath(userProfile);
    }

    final homeDrive = Platform.environment['HOMEDRIVE'];
    final homePath = Platform.environment['HOMEPATH'];
    if (homeDrive != null &&
        homePath != null &&
        homeDrive.isNotEmpty &&
        homePath.isNotEmpty) {
      return _normalizeHomePath('$homeDrive$homePath');
    }

    return _normalizeHomePath(Directory.current.path);
  }

  static String defaultSkillsDirectoryPath() {
    return p.join(homeDirectoryPath(), '.openhand', 'skills');
  }

  static String defaultSettingsDirectoryPath() {
    return p.join(homeDirectoryPath(), '.openhand', 'settings');
  }

  static String defaultSettingsFilePath() {
    return p.join(defaultSettingsDirectoryPath(), 'SETTINGS.toml');
  }

  static String defaultMcpDirectoryPath() {
    return p.join(homeDirectoryPath(), '.openhand', 'mcp');
  }

  static String defaultMcpServersFilePath() {
    return p.join(defaultMcpDirectoryPath(), 'mcp_servers.json');
  }

  static String defaultSessionsDirectoryPath() {
    return p.join(homeDirectoryPath(), '.openhand', 'sessions');
  }

  static String applicationDirectoryPath() {
    return p.normalize(Directory.current.path);
  }

  static String defaultMemoryDirectoryPath() {
    return p.join(applicationDirectoryPath(), '.openhand', 'memory');
  }

  static String defaultUserMemoryFilePath() {
    return p.join(defaultMemoryDirectoryPath(), 'user-memory.json');
  }

  static String defaultUserMemoryFileLabel() {
    return shortenHomePath(defaultUserMemoryFilePath());
  }

  static String normalizeUserPath(String? rawPath) {
    return normalizePath(rawPath, defaultPath: defaultSkillsDirectoryPath());
  }

  static String normalizePath(String? rawPath, {required String defaultPath}) {
    if (rawPath == null || rawPath.trim().isEmpty) {
      return defaultPath;
    }

    final trimmed = rawPath.trim();
    if (trimmed == '~') {
      return homeDirectoryPath();
    }
    if (trimmed.startsWith('~/') || trimmed.startsWith(r'~\')) {
      return p.normalize(p.join(homeDirectoryPath(), trimmed.substring(2)));
    }
    return p.normalize(trimmed);
  }

  static String shortenHomePath(String path) {
    final normalizedPath = p.normalize(path);
    final normalizedHome = homeDirectoryPath();
    if (p.equals(normalizedPath, normalizedHome)) {
      return '~';
    }
    if (p.isWithin(normalizedHome, normalizedPath)) {
      return p.join('~', p.relative(normalizedPath, from: normalizedHome));
    }
    return normalizedPath;
  }

  static String basename(String path) {
    return p.basename(path);
  }

  static String? legacySandboxSettingsFilePath() {
    if (!Platform.isMacOS) {
      return null;
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.trim().isEmpty) {
      return null;
    }
    final normalizedHome = p.normalize(home);
    final sandboxMarker =
        '${p.separator}Library${p.separator}Containers${p.separator}';
    if (!normalizedHome.contains(sandboxMarker)) {
      return null;
    }
    return p.join(normalizedHome, '.openhand', 'settings', 'SETTINGS.toml');
  }

  static String _normalizeHomePath(String rawPath) {
    final normalizedPath = p.normalize(rawPath);
    if (!Platform.isMacOS) {
      return normalizedPath;
    }
    final sandboxMarker =
        '${p.separator}Library${p.separator}Containers${p.separator}';
    final markerIndex = normalizedPath.indexOf(sandboxMarker);
    if (markerIndex <= 0) {
      return normalizedPath;
    }
    return normalizedPath.substring(0, markerIndex);
  }
}
