import 'dart:io';

import 'package:path/path.dart' as p;

import '../../shared/util/input_value_parsing.dart';

abstract final class OpenHandPaths {
  static const String defaultSkillsDirectoryLabel = '~/.openhand/skills';

  static const String defaultMcpServersFileLabel =
      '~/.openhand/mcp/mcp_servers.json';

  static String homeDirectoryPath() {
    final home = nullIfBlank(Platform.environment['HOME']);
    if (home != null) {
      return _normalizeHomePath(home);
    }

    final userProfile = nullIfBlank(Platform.environment['USERPROFILE']);
    if (userProfile != null) {
      return _normalizeHomePath(userProfile);
    }

    final homeDrive = nullIfBlank(Platform.environment['HOMEDRIVE']);
    final homePath = nullIfBlank(Platform.environment['HOMEPATH']);
    if (homeDrive != null && homePath != null) {
      return _normalizeHomePath('$homeDrive$homePath');
    }

    return _normalizeHomePath(Directory.current.path);
  }

  static String defaultSkillsDirectoryPath() {
    return p.join(homeDirectoryPath(), '.openhand', 'skills');
  }

  static String defaultLspDirectoryPath() {
    return p.join(homeDirectoryPath(), '.openhand', 'lsp');
  }

  static String defaultLspDirectoryPathForLanguage(String language) {
    return p.join(defaultLspDirectoryPath(), language.trim());
  }

  static String defaultLspDirectoryLabelForLanguage(String language) {
    return shortenHomePath(defaultLspDirectoryPathForLanguage(language));
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

  static String defaultDatabasePath() {
    return p.join(homeDirectoryPath(), '.openhand', 'openhand.db');
  }

  static String defaultSessionAttachmentsDirectoryPath() {
    return p.join(defaultSessionsDirectoryPath(), 'attachments');
  }

  /// Root directory used for all OpenHand on-disk artifacts (`~/.openhand`).
  /// Centralising this path keeps the data-cleanup module aligned with the
  /// rest of the storage layout and avoids ad-hoc `p.join(home, '.openhand')`
  /// duplication across features.
  static String defaultRootDirectoryPath() {
    return p.join(homeDirectoryPath(), '.openhand');
  }

  /// Filesystem cache directory used by background workers and best-effort
  /// scratch space. The directory is created lazily by callers and may be
  /// absent on a fresh install.
  static String defaultCacheDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'cache');
  }

  /// Persistent cache for remote AI media URLs (images / videos / audio).
  ///
  /// This is deliberately nested under the app cache root while data-cleanup
  /// treats it as multimedia data, so users can audit and clear generated media
  /// cache without wiping unrelated worker caches.
  static String defaultMediaCacheDirectoryPath() {
    return p.join(defaultCacheDirectoryPath(), 'media');
  }

  static String defaultMessageGatewayDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'message_gateway');
  }

  /// Logs directory used by background workers for opt-in disk logging.
  /// May be absent on a fresh install.
  static String defaultLogsDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'logs');
  }

  static String applicationDirectoryPath() {
    return p.normalize(Directory.current.path);
  }

  static String defaultMemoryDirectoryPath() {
    return p.join(homeDirectoryPath(), '.openhand', 'memory');
  }

  static String defaultUserMemoryFilePath() {
    return p.join(defaultMemoryDirectoryPath(), 'user-memory.json');
  }

  static String normalizeUserPath(String? rawPath) {
    return normalizePath(rawPath, defaultPath: defaultSkillsDirectoryPath());
  }

  static String normalizeOptionalPath(String? rawPath) {
    final trimmed = nullIfBlank(rawPath);
    if (trimmed == null) {
      return '';
    }
    return _normalizeExpandedPath(trimmed);
  }

  static String normalizePath(String? rawPath, {required String defaultPath}) {
    final trimmed = nullIfBlank(rawPath);
    if (trimmed == null) {
      return defaultPath;
    }
    return _normalizeExpandedPath(trimmed);
  }

  static String _normalizeExpandedPath(String trimmed) {
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
