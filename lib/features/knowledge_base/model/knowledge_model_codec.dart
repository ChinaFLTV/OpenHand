import '../../../shared/util/input_value_parsing.dart';

DateTime? knowledgeDate(Object? value) {
  return utcDateTimeFromValue(value);
}

Map<String, Object?> knowledgeJsonMap(Object? value) {
  final text = value is String ? nullIfBlank(value) : null;
  if (text == null) return const {};
  return stringKeyedMapFromJsonText(text);
}

String? knowledgeNullableString(Object? value) {
  final text = nullIfBlank('${value ?? ''}');
  return text == null || text == 'null' ? null : text;
}
