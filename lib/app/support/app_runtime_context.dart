import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import '../../shared/util/localized_text.dart';
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
    'auth',
    'sock',
    'proxy',
    'passphrase',
    'signature',
    'bearer',
  ];

  static AppInfo _appInfo = AppInfo.fallback();
  static Locale _appLocale = _normalizeLocale(
    PlatformDispatcher.instance.locale,
  );

  static void initialize(AppInfo appInfo, {Locale? appLocale}) {
    _appInfo = appInfo;
    _appLocale = _normalizeLocale(
      appLocale ?? PlatformDispatcher.instance.locale,
    );
  }

  static Locale get appLocale => _appLocale;

  static String pickText({
    required String zh,
    required String en,
    String? zhHans,
    String? zhHant,
    String? fr,
    String? de,
    String? ja,
  }) {
    return openHandLocalizedTextForLocale(
      _appLocale,
      zh: zh,
      en: en,
      zhHans: zhHans,
      zhHant: zhHant,
      fr: fr,
      de: de,
      ja: ja,
    );
  }

  static void updateAppLocale(Locale locale) {
    _appLocale = _normalizeLocale(locale);
  }

  static Locale _normalizeLocale(Locale locale) {
    if (locale.languageCode != 'zh') {
      return Locale(locale.languageCode);
    }
    return Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: locale.scriptCode == 'Hant' ? 'Hant' : 'Hans',
    );
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
    final merged = <String, String>{...Platform.environment, ...overrides};

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
