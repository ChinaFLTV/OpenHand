import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'bounded_json_conversion.dart';

const int kStableFnv1a32OffsetBasis = 0x811c9dc5;
const int kStableFnv1a32Prime = 0x01000193;
const int kStableFnv1a32Mask = 0xffffffff;
const int kStableSha256HexLength = 64;

String stableFnv1a32Hex(String content) {
  var hash = kStableFnv1a32OffsetBasis;
  for (final codeUnit in content.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * kStableFnv1a32Prime) & kStableFnv1a32Mask;
  }
  return hash.toUnsigned(32).toRadixString(16).padLeft(8, '0');
}

String stableSha256Hex(String content, {int length = kStableSha256HexLength}) {
  final full = crypto.sha256.convert(utf8.encode(content)).toString();
  final safeLength = length.clamp(1, full.length).toInt();
  return full.substring(0, safeLength);
}

/// 对 JSON 类数据有界规范化后计算稳定指纹，不受 Map 插入顺序影响。
String stableJsonSha256(Object? value) {
  final safeValue = convertToJsonSafeValue(value);
  return stableSha256Hex(jsonEncode(_canonicalJsonValue(safeValue)));
}

Object? _canonicalJsonValue(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    return value.isFinite ? value : value.toString();
  }
  if (value is num) return value;
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Enum) return value.name;
  if (value is Map) {
    final entries = <MapEntry<String, Object?>>[];
    value.forEach((key, child) {
      entries.add(
        MapEntry<String, Object?>('$key', _canonicalJsonValue(child)),
      );
    });
    entries.sort((a, b) {
      final keyOrder = a.key.compareTo(b.key);
      if (keyOrder != 0) return keyOrder;
      return jsonEncode(a.value).compareTo(jsonEncode(b.value));
    });
    return <String, Object?>{
      for (final entry in entries) entry.key: entry.value,
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalJsonValue).toList(growable: false);
  }
  return '$value';
}
