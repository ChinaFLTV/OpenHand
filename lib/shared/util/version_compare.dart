import 'input_value_parsing.dart';

final RegExp _looseVersionTokenPattern = RegExp(r'\d+(?:\.\d+)*');
final RegExp _strictSemanticVersionPattern = RegExp(r'^\d+\.\d+\.\d+$');
final RegExp _leadingVersionPrefixPattern = RegExp('^[vV]');

List<int> versionPartsFromText(String value) {
  final normalized = value
      .trim()
      .replaceFirst(_leadingVersionPrefixPattern, '')
      .split('+')
      .first
      .split('-')
      .first;
  final raw = _looseVersionTokenPattern.firstMatch(normalized)?.group(0);
  if (raw == null) return const <int>[];
  return raw
      .split('.')
      .map((part) => optionalNonNegativeIntFromValue(part) ?? 0)
      .toList(growable: false);
}

int? versionMajorFromText(String value) {
  final parts = versionPartsFromText(value);
  return parts.isEmpty ? null : parts.first;
}

bool isStrictSemanticVersionText(String value) {
  return _strictSemanticVersionPattern.hasMatch(value.trim());
}

int compareVersionParts(List<int> a, List<int> b, {int minimumSegments = 3}) {
  final safeMinimumSegments = minimumSegments < 0 ? 0 : minimumSegments;
  final maxLength = [
    safeMinimumSegments,
    a.length,
    b.length,
  ].reduce((value, element) => value > element ? value : element);
  for (var index = 0; index < maxLength; index++) {
    final av = index < a.length ? a[index] : 0;
    final bv = index < b.length ? b[index] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

int compareSemanticVersions(
  String a,
  String b, {
  int minimumSegments = 3,
  bool lexicalFallback = true,
}) {
  final ap = versionPartsFromText(a);
  final bp = versionPartsFromText(b);
  if (ap.isEmpty || bp.isEmpty) {
    return lexicalFallback ? a.compareTo(b) : compareVersionParts(ap, bp);
  }
  return compareVersionParts(ap, bp, minimumSegments: minimumSegments);
}
