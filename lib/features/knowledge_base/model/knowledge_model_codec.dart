import 'dart:convert';

DateTime? knowledgeDate(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text)?.toUtc();
}

Map<String, Object?> knowledgeJsonMap(Object? value) {
  if (value is! String || value.trim().isEmpty) return const {};
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  } catch (_) {}
  return const {};
}

String? knowledgeNullableString(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty || text == 'null' ? null : text;
}
