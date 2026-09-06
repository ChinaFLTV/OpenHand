import 'dart:math' as math;

import 'stable_hash.dart';

const int kOpenHandDefaultToolNameMaxLength = 64;

final RegExp _unsafeToolNameCharsPattern = RegExp('[^A-Za-z0-9_-]+');
final RegExp _edgeUnderscoresPattern = RegExp(r'^_+|_+$');

String normalizeToolNameToken(String value, {String fallback = 'tool'}) {
  final sanitized = _sanitizeToolNameToken(value);
  if (sanitized.isNotEmpty) return sanitized;
  final sanitizedFallback = _sanitizeToolNameToken(fallback);
  return sanitizedFallback.isEmpty ? 'tool' : sanitizedFallback;
}

String _sanitizeToolNameToken(String value) {
  return value
      .trim()
      .replaceAll(_unsafeToolNameCharsPattern, '_')
      .replaceAll(_edgeUnderscoresPattern, '');
}

String compactToolName({
  required String prefix,
  required String token,
  int maxLength = kOpenHandDefaultToolNameMaxLength,
}) {
  final safeMaxLength = math.max(1, maxLength);
  final normalizedPrefix = normalizeToolNameToken(prefix);
  final normalizedToken = normalizeToolNameToken(token);
  var candidate = '${normalizedPrefix}__$normalizedToken';
  if (candidate.length <= safeMaxLength) return candidate;

  final hash = stableFnv1a32Hex(token);
  final allowedTokenLength =
      safeMaxLength - normalizedPrefix.length - hash.length - 4;
  final preferredLength =
      allowedTokenLength > 8 && allowedTokenLength < normalizedToken.length
      ? allowedTokenLength
      : (normalizedToken.length < 24 ? normalizedToken.length : 24);
  final safePreferredLength = preferredLength.clamp(1, normalizedToken.length);
  final shortenedToken = normalizedToken.substring(0, safePreferredLength);
  candidate = '${normalizedPrefix}__${shortenedToken}_$hash';
  return candidate.length > safeMaxLength
      ? candidate.substring(0, safeMaxLength)
      : candidate;
}

String appendUniqueToolNameSuffix(
  String candidate,
  int suffix, {
  int maxLength = kOpenHandDefaultToolNameMaxLength,
}) {
  final suffixToken = '_$suffix';
  final safeMaxLength = math.max(1, maxLength);
  final baseLength = math.max(1, safeMaxLength - suffixToken.length);
  final base = candidate.length > baseLength
      ? candidate.substring(0, baseLength)
      : candidate;
  final value = '$base$suffixToken';
  return value.length > safeMaxLength
      ? value.substring(0, safeMaxLength)
      : value;
}
