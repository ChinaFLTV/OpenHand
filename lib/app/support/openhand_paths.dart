import 'dart:io';

import 'package:path/path.dart' as p;

import '../../shared/util/input_value_parsing.dart';

abstract final class OpenHandPaths {
  static const String defaultSkillsDirectoryLabel = '~/.openhand/skills';

  static String homeDirectoryPath() {
    return environmentHomeDirectoryPath() ??
        _normalizeHomePath(p.absolute(Directory.current.path));
  }

  static String? environmentHomeDirectoryPath() {
    final home = nullIfBlank(Platform.environment['HOME']);
    if (home != null && p.isAbsolute(home)) {
      return _normalizeHomePath(home);
    }

    final userProfile = nullIfBlank(Platform.environment['USERPROFILE']);
    if (userProfile != null && p.isAbsolute(userProfile)) {
      return _normalizeHomePath(userProfile);
    }

    final homeDrive = nullIfBlank(Platform.environment['HOMEDRIVE']);
    final homePath = nullIfBlank(Platform.environment['HOMEPATH']);
    final windowsHome = homeDrive != null && homePath != null
        ? '$homeDrive$homePath'
        : null;
    if (windowsHome != null && p.isAbsolute(windowsHome)) {
      return _normalizeHomePath(windowsHome);
    }
    return null;
  }

  static String defaultSkillsDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'skills');
  }

  static String defaultLspDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'lsp');
  }

  static String defaultLspDirectoryPathForLanguage(String language) {
    return p.join(defaultLspDirectoryPath(), language.trim());
  }

  static String defaultLspDirectoryLabelForLanguage(String language) {
    return shortenHomePath(defaultLspDirectoryPathForLanguage(language));
  }

  static String defaultMcpDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'mcp');
  }

  static String defaultMcpServersFilePath() {
    return p.join(defaultMcpDirectoryPath(), 'mcp_servers.json');
  }

  static String defaultSessionsDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'sessions');
  }

  static String defaultDatabasePath() {
    return p.join(defaultRootDirectoryPath(), 'openhand.db');
  }

  static String defaultToolUsagePromotionFilePath() {
    return p.join(defaultRootDirectoryPath(), 'tool_usage_promotion.json');
  }

  /// OpenHand 所有磁盘数据的默认根目录（`~/.openhand`）。
  static String defaultRootDirectoryPath() {
    return p.join(homeDirectoryPath(), '.openhand');
  }

  static String defaultAndroidReverseToolsDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'android_reverse_tools');
  }

  /// 后台任务与临时文件共用的缓存目录，由调用方按需创建。
  static String defaultCacheDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'cache');
  }

  /// 远程 AI 图片、视频和音频的持久缓存目录。
  static String defaultMediaCacheDirectoryPath() {
    return p.join(defaultCacheDirectoryPath(), 'media');
  }

  static String defaultMessageGatewayDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'message_gateway');
  }

  static String defaultHooksTemporaryDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'hooks', 'tmp');
  }

  static String defaultAiExposureServiceDirectoryPath() {
    return p.join(
      defaultRootDirectoryPath(),
      'services',
      'ai_infrastructure_exposure',
    );
  }

  /// 后台任务按需写入的日志目录。
  static String defaultLogsDirectoryPath() {
    return p.join(defaultRootDirectoryPath(), 'logs');
  }

  static String applicationDirectoryPath() {
    return p.normalize(Directory.current.path);
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
