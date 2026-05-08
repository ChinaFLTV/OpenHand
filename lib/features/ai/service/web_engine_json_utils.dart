/// WebSearch / WebFetch 引擎适配器共用的 JSON 解析帮手。
///
/// 这里只放与具体引擎无关的、纯 stateless 的工具函数；和领域模型耦合的逻辑
/// 仍保留在各自包内（`web_search/`、`web_fetch/`）。
library;

import 'dart:convert';

/// JSON 解析容错：忽略空值、自动 trim，统一返回 String。
String stringOf(Object? raw, {String fallback = ''}) {
  if (raw == null) return fallback;
  if (raw is String) return raw.trim();
  return '$raw'.trim();
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
