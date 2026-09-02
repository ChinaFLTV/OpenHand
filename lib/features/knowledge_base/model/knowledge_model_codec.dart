import 'dart:convert';

import '../../../shared/util/input_value_parsing.dart';

DateTime? knowledgeDate(
  Object? value, {
  required String field,
  bool nullable = true,
}) {
  if (value == null && nullable) return null;
  if (value is! String) throw FormatException('$field 必须为 UTC 时间文本。');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$field 不是有效 UTC 时间。');
  }
  return parsed;
}

Map<String, Object?> knowledgeJsonMap(Object? value, {required String field}) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field 必须为 JSON 对象文本。');
  }
  final decoded = jsonDecode(value);
  if (decoded is! Map) throw FormatException('$field 必须为 JSON 对象。');
  final result = stringKeyedMapFromValue(decoded);
  validateCanonicalJsonSubset(
    result,
    result,
    path: field,
    maxDepth: 32,
    maxContainerItems: 4096,
    maxTotalNodes: 32768,
  );
  return Map<String, Object?>.unmodifiable(result);
}

String knowledgeText(
  Map<String, Object?> row,
  String key, {
  bool allowEmpty = true,
  int? maxCharacters,
}) {
  final value = row[key];
  if (value is! String ||
      (!allowEmpty && value.isEmpty) ||
      (maxCharacters != null && value.length > maxCharacters)) {
    throw FormatException('知识字段 $key 无效。');
  }
  return value;
}

int knowledgeNonNegativeInt(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! int || value < 0) {
    throw FormatException('知识字段 $key 必须为非负整数。');
  }
  return value;
}

int? knowledgeOptionalNonNegativeInt(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw FormatException('知识字段 $key 必须为非负整数。');
  }
  return value;
}

String? knowledgeNullableString(
  Object? value, {
  required String field,
  int? maxCharacters,
}) {
  if (value == null || value == '') return null;
  if (value is! String ||
      value.trim() != value ||
      (maxCharacters != null && value.length > maxCharacters)) {
    throw FormatException('$field 无效。');
  }
  return value;
}

String knowledgeEncodeJsonMap(
  Map<String, Object?> value, {
  required String field,
}) {
  validateCanonicalJsonSubset(
    value,
    value,
    path: field,
    maxDepth: 32,
    maxContainerItems: 4096,
    maxTotalNodes: 32768,
  );
  return jsonEncode(value);
}
