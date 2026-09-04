import 'dart:convert';

import '../../../../shared/util/bounded_json_conversion.dart';
import '../../../../shared/util/input_value_parsing.dart';

const BoundedJsonConversionConfig _webEngineJsonConversionConfig =
    BoundedJsonConversionConfig(
      maxTotalNodes: 200000,
      nonFiniteNumberBehavior: JsonNonFiniteNumberBehavior.zero,
    );

Object? decodeWebEngineJsonText(String text, {required int maxTextCodeUnits}) {
  return decodeJsonTextUsingConfig(
    text,
    maxTextCodeUnits: maxTextCodeUnits,
    config: _webEngineJsonConversionConfig,
  );
}

/// JSON 解析容错：忽略空值、自动 trim，统一返回 String。
String stringOf(Object? raw, {String fallback = ''}) {
  return stringFromValue(raw, fallback: fallback);
}

/// 把 JSON Map 统一收敛为 String key，非 Map 输入返回空 Map。
Map<String, Object?> jsonObjectOf(Object? raw) {
  return stringKeyedMapFromValue(raw);
}

/// 解码 HTTP 响应体，要求根节点必须是 JSON Object。
Map<String, Object?> decodeJsonObjectBytes(
  List<int> bodyBytes, {
  String source = 'response body',
}) {
  final text = utf8.decode(bodyBytes, allowMalformed: true).trim();
  if (text.isEmpty) {
    throw FormatException('$source is empty.');
  }
  final decoded = decodeWebEngineJsonText(
    text,
    maxTextCodeUnits: bodyBytes.length,
  );
  if (decoded is! Map) {
    throw FormatException('$source must be a JSON object.');
  }
  return stringKeyedMapFromValue(decoded);
}

/// 把 Map 有界递归转换为可安全编码的形态：key 转为 String，非有限数值
/// 替换为 0，并截断循环引用或超限容器。
Map<String, Object?> jsonSafeMap(Map<Object?, Object?> value) {
  return convertToJsonSafeMap(value, config: _webEngineJsonConversionConfig);
}

/// 把任意 Map 解码成嵌套 Map / List 安全版本。
T? readJsonPath<T>(Object? root, List<Object> path) {
  Object? cur = root;
  for (final seg in path) {
    if (cur is Map && seg is String && cur.containsKey(seg)) {
      cur = cur[seg];
    } else if (cur is List && seg is int && seg >= 0 && seg < cur.length) {
      cur = cur[seg];
    } else {
      return null;
    }
  }
  return cur is T ? cur : null;
}
