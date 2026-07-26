import 'dart:io';

import 'package:characters/characters.dart';

import '../model/app_info.dart';
import 'openhand_paths.dart';

/// 收集 Cron 执行历史所需的运行环境快照。
abstract final class AppRuntimeContext {
  static const List<String> _sensitiveEnvKeyTokens = <String>[
    'password',
    'passwd',
    'secret',
    'token',
    'api_key',
    'apikey',
    'access_key',
    'secret_key',
    'private_key',
    'credential',
    'authorization',
    'cookie',
    'session_token',
    'auth',
    'sock',
    'proxy',
    'passphrase',
    'signature',
    'bearer',
  ];

  static AppInfo _appInfo = AppInfo.fallback();

  static void initialize(AppInfo appInfo) {
    _appInfo = appInfo;
  }

  static Map<String, String> captureContext({
    required bool includeAppMetadata,
    required bool includeHostMetadata,
  }) {
    final result = <String, String>{
      'runtime.timestamp': DateTime.now().toIso8601String(),
    };

    if (includeAppMetadata) {
      result.addAll(<String, String>{
        'app.name': _appInfo.appName,
        'app.package': _appInfo.packageName,
        'app.version': _appInfo.version,
        'app.build': _appInfo.buildNumber,
        'app.display_version': _appInfo.displayVersion,
        'app.pid': '$pid',
        'app.executable': Platform.resolvedExecutable,
        'app.cwd': OpenHandPaths.applicationDirectoryPath(),
      });
    }

    if (includeHostMetadata) {
      final hostName = _safeLocalHostName();
      result.addAll(<String, String>{
        'host.os': Platform.operatingSystem,
        'host.os_version': Platform.operatingSystemVersion,
        'host.locale': Platform.localeName,
        'host.cpu_cores': '${Platform.numberOfProcessors}',
        if (hostName != null) 'host.hostname': hostName,
      });
    }

    return result;
  }

  static Map<String, String> captureEnvironmentSnapshot(
    Map<String, String> overrides, {
    int maxEntries = 120,
    int maxValueChars = 512,
  }) {
    final entryLimit = maxEntries < 0 ? 0 : maxEntries;
    final valueCharLimit = maxValueChars < 0 ? 0 : maxValueChars;
    final merged = <String, String>{...Platform.environment, ...overrides};

    final keys = merged.keys.toList()
      ..sort((left, right) {
        final leftIsOverride = overrides.containsKey(left);
        final rightIsOverride = overrides.containsKey(right);
        if (leftIsOverride != rightIsOverride) return leftIsOverride ? -1 : 1;
        return left.compareTo(right);
      });
    final result = <String, String>{};
    var maskedCount = 0;
    for (var i = 0; i < keys.length && i < entryLimit; i++) {
      final key = keys[i];
      if (_isSensitiveEnvKey(key)) {
        result[key] = '***已隐藏***';
        maskedCount++;
        continue;
      }
      final rawValue = merged[key] ?? '';
      final valueCharacters = rawValue.characters;
      final characterCount = valueCharacters.length;
      if (characterCount <= valueCharLimit) {
        result[key] = rawValue;
      } else {
        result[key] =
            '${valueCharacters.take(valueCharLimit)}…'
            '（已截断 ${characterCount - valueCharLimit} 个字符）';
      }
    }

    if (keys.length > entryLimit) {
      result['_meta.truncated_keys'] = '${keys.length - entryLimit} 个键已省略';
    }
    if (maskedCount > 0) {
      result['_meta.masked_keys'] = '$maskedCount 个敏感值已隐藏';
    }
    return result;
  }

  static String? _safeLocalHostName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return null;
    }
  }

  static bool _isSensitiveEnvKey(String key) {
    final normalized = key.toLowerCase();
    return _sensitiveEnvKeyTokens.any(normalized.contains);
  }
}
