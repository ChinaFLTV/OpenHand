import 'text_clip.dart';

const String kOpenHandRedactedValue = '[redacted]';
const String _redactedUriUserInfo = 'redacted';

final RegExp _sensitiveKeySeparator = RegExp('[^a-z0-9]+');
final RegExp _sensitiveCamelCaseBoundary = RegExp('([a-z0-9])([A-Z])');
const Set<String> _sensitiveExactKeys = <String>{'cookie', 'set-cookie'};

/// 固定遍历长度比较凭据，避免普通字符串短路比较泄露首个差异位置。
bool constantTimeStringEquals(String left, String right) {
  final leftUnits = left.codeUnits;
  final rightUnits = right.codeUnits;
  final length = leftUnits.length > rightUnits.length
      ? leftUnits.length
      : rightUnits.length;
  var difference = leftUnits.length ^ rightUnits.length;
  for (var index = 0; index < length; index++) {
    final leftUnit = index < leftUnits.length ? leftUnits[index] : 0;
    final rightUnit = index < rightUnits.length ? rightUnits[index] : 0;
    difference |= leftUnit ^ rightUnit;
  }
  return difference == 0;
}

/// 整体或以 `-` 结尾即视为凭据的键名。
///
/// 用「整体相等或以 `-<后缀>` 结尾」而不是子串包含：`authorization-scope`
/// 这类描述性字段不该被抹掉，抹掉了排查请求头问题就没了线索。
///
/// 后半段的连写形式（`apikey` / `accesstoken` …）是必要的：模型与 MCP 都允许
/// 用户自填请求头，而这些写法按 `-` 切词后是一个整词，走不到下面的分词匹配，
/// 此前会原样落进会话遥测并随导出文件一起带走。
const List<String> _sensitiveKeySuffixes = <String>[
  'authorization',
  'authentication',
  'api-key',
  'access-key',
  'private-key',
  'secret-key',
  'apikey',
  'apisecret',
  'apitoken',
  'accesskey',
  'accesstoken',
  'secretkey',
  'privatekey',
  'authtoken',
  'refreshtoken',
  'idtoken',
  'sessiontoken',
  'bearertoken',
];

/// 按 `-` 切词后命中任一即视为凭据。
///
/// 刻意不收 `tokens`：`total_tokens`、`cache_read_tokens` 这类计数不是凭据，
/// 抹掉会让用量统计失真。
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
  if (_sensitiveExactKeys.contains(normalized)) return true;
  for (final suffix in _sensitiveKeySuffixes) {
    if (normalized == suffix || normalized.endsWith('-$suffix')) return true;
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
