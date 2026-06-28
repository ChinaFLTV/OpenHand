import '../../../shared/util/input_value_parsing.dart';

DateTime? knowledgeDate(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text)?.toUtc();
}

Map<String, Object?> knowledgeJsonMap(Object? value) {
  if (value is! String || value.trim().isEmpty) return const {};
  return stringKeyedMapFromJsonText(value);
}

String? knowledgeNullableString(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty || text == 'null' ? null : text;
}
