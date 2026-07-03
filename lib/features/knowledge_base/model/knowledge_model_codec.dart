import '../../../shared/util/input_value_parsing.dart';

DateTime? knowledgeDate(Object? value) {
  return utcDateTimeFromValue(value);
}

Map<String, Object?> knowledgeJsonMap(Object? value) {
  if (value is! String || value.trim().isEmpty) return const {};
  return stringKeyedMapFromJsonText(value);
}

String? knowledgeNullableString(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty || text == 'null' ? null : text;
}
