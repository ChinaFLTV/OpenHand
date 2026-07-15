import 'text_clip.dart';

const String kOpenHandRedactedValue = '[redacted]';
const String _redactedUriUserInfo = 'redacted';

final RegExp _sensitiveKeySeparator = RegExp(r'[^a-z0-9]+');
final RegExp _sensitiveCamelCaseBoundary = RegExp(r'([a-z0-9])([A-Z])');
const Set<String> _sensitiveExactKeys = <String>{
  'authorization',
  'cookie',
  'proxy-authorization',
  'set-cookie',
};
const Set<String> _sensitiveKeySegments = <String>{
  'credential',
  'credentials',
  'passwd',
  'password',
  'secret',
  'signature',
  'token',
};

bool isSensitiveDataKey(String key) {
  final normalized = key
      .trim()
      .replaceAllMapped(
        _sensitiveCamelCaseBoundary,
        (match) => '${match.group(1)}-${match.group(2)}',
      )
      .toLowerCase()
      .replaceAll(_sensitiveKeySeparator, '-');
  if (normalized.isEmpty) return false;
  if (_sensitiveExactKeys.contains(normalized) ||
      normalized == 'api-key' ||
      normalized.endsWith('-api-key') ||
      normalized == 'access-key' ||
      normalized.endsWith('-access-key') ||
      normalized == 'private-key' ||
      normalized.endsWith('-private-key') ||
      normalized == 'secret-key' ||
      normalized.endsWith('-secret-key')) {
    return true;
  }
  return normalized.split('-').any(_sensitiveKeySegments.contains);
}

Map<String, String> redactSensitiveStringMap(
  Map<String, String> values, {
  int maxEntries = 64,
  int maxKeyCharacters = 128,
  int maxValueCharacters = 512,
}) {
  if (values.isEmpty ||
      maxEntries <= 0 ||
      maxKeyCharacters <= 0 ||
      maxValueCharacters < 0) {
    return const <String, String>{};
  }
  final result = <String, String>{};
  for (final entry in values.entries) {
    if (result.length >= maxEntries) break;
    final key = clipText(entry.key.trim(), maxKeyCharacters, suffix: '');
    if (key.isEmpty) continue;
    result[key] = isSensitiveDataKey(entry.key)
        ? kOpenHandRedactedValue
        : clipText(entry.value, maxValueCharacters, suffix: '');
  }
  return Map<String, String>.unmodifiable(result);
}

String redactSensitiveUriForLogging(String? value, {int maxCharacters = 1024}) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty || maxCharacters <= 0) return '';
  final uri = Uri.tryParse(raw);
  if (uri == null) {
    final queryIndex = raw.indexOf('?');
    final safe = queryIndex < 0
        ? raw
        : '${raw.substring(0, queryIndex)}?[query redacted]';
    return clipText(safe, maxCharacters, suffix: '');
  }
  final sanitized = uri.hasQuery
      ? redactSensitiveStringMap(uri.queryParameters)
      : const <String, String>{};
  final hasUserInfo = uri.hasAuthority && uri.userInfo.isNotEmpty;
  return clipText(
    uri
        .replace(
          userInfo: hasUserInfo ? _redactedUriUserInfo : null,
          queryParameters: uri.hasQuery
              ? (sanitized.isEmpty ? null : sanitized)
              : null,
        )
        .toString(),
    maxCharacters,
    suffix: '',
  );
}
