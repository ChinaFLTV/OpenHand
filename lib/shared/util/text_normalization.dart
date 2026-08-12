/// 连续空白。共用同一个已编译实例：全库有二十余处按空白切分 / 折叠，其中
/// 若干位于输入框监听、逐行解析这类高频路径上，每次重新编译纯属浪费。
final RegExp kInlineWhitespacePattern = RegExp(r'\s+');
final RegExp _asciiLookupTokenSeparatorPattern = RegExp(r'[^a-z0-9]+');
final RegExp _snakeStorageKeySeparatorPattern = RegExp(r'[\s-]+');

/// 统一匹配 HTML/XML 标签，供错误页、TTS 和文档解析复用。
final RegExp kHtmlTagPattern = RegExp(r'<[^>]*>');

/// 连续三个及以上换行，供折叠多空行复用。
final RegExp kExcessiveNewlinesPattern = RegExp(r'\n{3,}');

/// 将连续空行折叠为至多两行换行，并 trim 首尾。
String collapseExcessiveNewlines(String value) {
  return value.replaceAll(kExcessiveNewlinesPattern, '\n\n').trim();
}

String collapseInlineWhitespace(String value) {
  return value.replaceAll(kInlineWhitespacePattern, ' ').trim();
}

/// 移除 HTML/XML 标签；默认以空格替换，传入空串可直接删除。
String stripHtmlTags(String value, {String replacement = ' '}) {
  return value.replaceAll(kHtmlTagPattern, replacement);
}

String removeInlineWhitespace(String value) {
  return value.replaceAll(kInlineWhitespacePattern, '');
}

/// 统计以空白分隔的词数；空串或纯空白返回 0。
int countWhitespaceSeparatedWords(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 0;
  var count = 0;
  for (final token in trimmed.split(kInlineWhitespacePattern)) {
    if (token.isNotEmpty) count += 1;
  }
  return count;
}

/// 判断是否为常见 ASCII 空白字符。
bool isAsciiWhitespaceCodeUnit(int codeUnit) {
  return codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D;
}

List<String> dedupeNonEmptyStrings(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    if (seen.add(value.toLowerCase())) result.add(value);
  }
  return result;
}

/// 仅保留 ASCII 字母数字并转为小写，用于宽松查找。
String normalizeAsciiLookupKey(String value) {
  final buffer = StringBuffer();
  for (final code in value.trim().codeUnits) {
    if (code >= 0x30 && code <= 0x39) {
      buffer.writeCharCode(code);
    } else if (code >= 0x41 && code <= 0x5A) {
      buffer.writeCharCode(code | 0x20);
    } else if (code >= 0x61 && code <= 0x7A) {
      buffer.writeCharCode(code);
    }
  }
  return buffer.toString();
}

String normalizeAsciiSlugKey(String value) {
  return value.trim().toLowerCase().replaceAll(
    _asciiLookupTokenSeparatorPattern,
    '-',
  );
}

String normalizeSnakeStorageKey(String value) {
  return value.trim().toLowerCase().replaceAll(
    _snakeStorageKeySeparatorPattern,
    '_',
  );
}
