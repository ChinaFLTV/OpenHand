import 'dart:io';

import '../model/app_info.dart';
import 'openhand_paths.dart';

/// Collects runtime snapshots used by Cron execution history records.
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
    final merged = <String, String>{
      ...Platform.environment,
      ...overrides,
    };

    final keys = merged.keys.toList()..sort();
    final result = <String, String>{};
    var maskedCount = 0;
    for (var i = 0; i < keys.length && i < maxEntries; i++) {
      final key = keys[i];
      if (_isSensitiveEnvKey(key)) {
        result[key] = '***masked***';
        maskedCount++;
        continue;
      }
      final rawValue = merged[key] ?? '';
      if (rawValue.length <= maxValueChars) {
        result[key] = rawValue;
      } else {
        result[key] =
            '${rawValue.substring(0, maxValueChars)}...(trimmed ${rawValue.length - maxValueChars} chars)';
      }
    }

    if (keys.length > maxEntries) {
      result['_meta.truncated_keys'] =
          '${keys.length - maxEntries} keys omitted';
    }
    if (maskedCount > 0) {
      result['_meta.masked_keys'] = '$maskedCount sensitive values masked';
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
