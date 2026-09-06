import 'dart:convert';

import 'rolling_hash.dart';

int boundedTextFingerprint(String value, {int edgeLength = 128}) {
  final safeEdgeLength = edgeLength <= 0 ? 1 : edgeLength;
  final length = value.length;
  if (length <= safeEdgeLength * 3) {
    return Object.hash(length, value);
  }

  final middleSampleLength = safeEdgeLength.clamp(1, length);
  final middleStart = (length ~/ 2 - middleSampleLength ~/ 2).clamp(
    0,
    length - middleSampleLength,
  );
  return Object.hash(
    length,
    value.substring(0, safeEdgeLength),
    value.substring(middleStart, middleStart + middleSampleLength),
    value.substring(length - safeEdgeLength),
  );
}

String compactTextSignature(
  Object? value, {
  int headLength = 48,
  int tailLength = 24,
  String emptySignature = '0',
}) {
  if (value == null) return emptySignature;
  final text = value is String ? value : _stringifySignatureValue(value);
  if (text.isEmpty) return emptySignature;

  final safeHeadLength = headLength < 0 ? 0 : headLength;
  final safeTailLength = tailLength < 0 ? 0 : tailLength;
  final headEnd = safeHeadLength > text.length ? text.length : safeHeadLength;
  final tailStart = safeTailLength <= 0
      ? text.length
      : (text.length - safeTailLength).clamp(headEnd, text.length);
  final head = text.substring(0, headEnd);
  final tail = tailStart < text.length ? text.substring(tailStart) : '';
  return '${text.length}:$head:$tail';
}

int scaledNumberSeriesFingerprint(Iterable<num> values, {int scale = 1000}) {
  final safeScale = scale == 0 ? 1 : scale.abs();
  return rollingHash30(values, (value) {
    if (!value.isFinite) return 0;
    return (value * safeScale).round();
  }, seed: values.length);
}

String _stringifySignatureValue(Object value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    try {
      return value.toString();
    } catch (_) {
      return value.runtimeType.toString();
    }
  }
}
