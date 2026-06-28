/// WebSearch / WebFetch 引擎适配器共用的 JSON 解析帮手。
///
/// 这里只放与具体引擎无关的、纯 stateless 的工具函数；和领域模型耦合的逻辑
/// 仍保留在各自包内（`web_search/`、`web_fetch/`）。
library;

import 'dart:convert';

import '../../../../shared/util/input_value_parsing.dart';

/// JSON 解析容错：忽略空值、自动 trim，统一返回 String。
String stringOf(Object? raw, {String fallback = ''}) {
  if (raw == null) return fallback;
  if (raw is String) return raw.trim();
  return '$raw'.trim();
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
  final decoded = jsonDecode(text);
  if (decoded is! Map) {
    throw FormatException('$source must be a JSON object.');
  }
  return stringKeyedMapFromValue(decoded);
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

/// JSON 解析帮手 — 输入是 String 时直接 jsonDecode；否则原样返回。
Object? maybeJsonDecode(Object? raw) {
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }
  return raw;
}
