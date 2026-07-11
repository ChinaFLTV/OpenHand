/// 纯函数辅助库——Web 逆向面板内部使用的小工具，独立成顶层公开 API
/// 以便 `test/` 直接覆盖（避免拖入 Flutter widget 依赖）。
library;

import 'dart:convert';

import '../../shared/util/input_value_parsing.dart';

const String _vlqAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const int _maxJwtNumericDateSeconds = 253402300799; // 9999-12-31T23:59:59Z.
final RegExp _consoleIsoTimestampPattern = RegExp(
  r'\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[^\s]*',
);
final RegExp _consoleHexPattern = RegExp(r'\b0x[0-9a-fA-F]+\b');
final RegExp _consoleLongNumberPattern = RegExp(r'\b\d{3,}\b');
final RegExp _consolePathHashPattern = RegExp(r'/[A-Fa-f0-9]{8,}');
final RegExp _consoleLocationTailPattern = RegExp(r':\d+:\d+\)');
final RegExp _consoleWhitespacePattern = RegExp(r'\s+');

/// 解码 source-map 中的 Base64 VLQ 段（不含 `,` 与 `;` 分隔符），
/// 返回该段内全部带符号整数。空串返回空列表，未知字符直接跳过。
List<int> vlqDecode(String s) {
  final result = <int>[];
  var value = 0;
  var shift = 0;
  for (final ch in s.codeUnits) {
    final digit = _vlqAlphabet.indexOf(String.fromCharCode(ch));
    if (digit < 0) continue;
    final cont = (digit & 32) != 0;
    final data = digit & 31;
    value |= data << shift;
    if (cont) {
      shift += 5;
    } else {
      final neg = (value & 1) != 0;
      var v = value >> 1;
      if (neg) v = -v;
      result.add(v);
      value = 0;
      shift = 0;
    }
  }
  return result;
}

/// 把 console 文本归一化为聚类签名：取首行，并把 ISO 时间戳、十六进制、
/// 长数字、URL 路径中的哈希摘要、行列尾 `:L:C)` 替换为占位符，
/// 再压缩连续空白。
String normalizeConsoleSignature(String text) {
  final firstLine = text.split('\n').first.trim();
  return firstLine
      .replaceAll(_consoleIsoTimestampPattern, '<ts>')
      .replaceAll(_consoleHexPattern, '<hex>')
      .replaceAll(_consoleLongNumberPattern, '<num>')
      .replaceAll(_consolePathHashPattern, '/<hash>')
      .replaceAll(_consoleLocationTailPattern, ':L:C)')
      .replaceAll(_consoleWhitespacePattern, ' ');
}

Object? cdpResultValue(Object? response) {
  if (response is! Map) return null;
  if (response['error'] != null) return null;
  final result = response['result'];
  if (result is! Map) return null;
  return result['value'];
}

String? cdpStringResultValue(Object? response) {
  final value = cdpResultValue(response);
  return value is String ? value : null;
}

Map<String, Object?>? decodeStringKeyedJsonMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? stringKeyedMapFromValue(decoded) : null;
  } catch (_) {
    return null;
  }
}

List<Object?>? decodeJsonList(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is List ? List<Object?>.of(decoded, growable: false) : null;
  } catch (_) {
    return null;
  }
}

List<Map<String, Object?>>? decodeStringKeyedJsonMapList(String raw) {
  final decoded = decodeJsonList(raw);
  return decoded == null ? null : stringKeyedMapListFromValue(decoded);
}

DateTime? jwtNumericDateFromValue(Object? value) {
  final seconds = optionalIntegralIntFromValue(value);
  if (seconds == null || seconds < 0 || seconds > _maxJwtNumericDateSeconds) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

Map<String, Object?>? cdpJsonMapStringResultValue(Object? response) {
  final raw = cdpStringResultValue(response);
  return raw == null ? null : decodeStringKeyedJsonMap(raw);
}
