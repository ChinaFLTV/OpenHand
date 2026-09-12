import 'input_value_parsing.dart';
import 'text_clip.dart';

const int kOpenHandJsonSchemaFieldDefaultLimit = 24;
const int kOpenHandJsonSchemaFieldDescriptionMaxChars = 160;

/// JSON Schema 一阶属性摘要，供悬停卡、目录预览等只读展示使用。
class OpenHandJsonSchemaField {
  const OpenHandJsonSchemaField({
    required this.name,
    required this.typeLabel,
    required this.required,
    this.description = '',
  });

  final String name;
  final String typeLabel;
  final bool required;
  final String description;
}

List<OpenHandJsonSchemaField> openHandJsonSchemaFields(
  Object? schema, {
  int maxFields = kOpenHandJsonSchemaFieldDefaultLimit,
}) {
  if (maxFields <= 0) return const <OpenHandJsonSchemaField>[];
  final schemaMap = optionalStringKeyedMapFromValue(schema);
  if (schemaMap == null) return const <OpenHandJsonSchemaField>[];
  final properties = optionalStringKeyedMapFromValue(schemaMap['properties']);
  if (properties == null || properties.isEmpty) {
    return const <OpenHandJsonSchemaField>[];
  }
  final requiredNames = stringListFromValue(schemaMap['required']).toSet();
  final fields = <OpenHandJsonSchemaField>[];
  for (final entry in properties.entries) {
    final name = entry.key.trim();
    if (name.isEmpty) continue;
    fields.add(
      OpenHandJsonSchemaField(
        name: name,
        typeLabel: openHandJsonSchemaTypeLabel(entry.value),
        required: requiredNames.contains(name),
        description: clipTextByCodeUnitsWithEllipsis(
          openHandJsonSchemaDescription(entry.value),
          kOpenHandJsonSchemaFieldDescriptionMaxChars,
        ),
      ),
    );
    if (fields.length >= maxFields) break;
  }
  return List<OpenHandJsonSchemaField>.unmodifiable(fields);
}

int openHandJsonSchemaPropertyCount(Object? schema) {
  final schemaMap = optionalStringKeyedMapFromValue(schema);
  final properties = optionalStringKeyedMapFromValue(schemaMap?['properties']);
  return properties?.length ?? 0;
}

String openHandJsonSchemaDescription(Object? schema) {
  final schemaMap = optionalStringKeyedMapFromValue(schema);
  if (schemaMap == null) return '';
  final description = schemaMap['description'];
  return description is String ? description.trim() : '';
}

String openHandJsonSchemaTypeLabel(Object? schema) {
  final schemaMap = optionalStringKeyedMapFromValue(schema);
  if (schemaMap == null) return '';
  final typeValue = schemaMap['type'];
  if (typeValue is String && typeValue.trim().isNotEmpty) {
    return typeValue.trim();
  }
  if (typeValue is List) {
    final values = stringListFromValue(typeValue);
    if (values.isNotEmpty) return values.join(' | ');
  }
  if (schemaMap['enum'] is List) return 'enum';
  if (schemaMap.containsKey('items')) return 'array';
  if (optionalStringKeyedMapFromValue(schemaMap['properties']) != null) {
    return 'object';
  }
  for (final keyword in const <String>['oneOf', 'anyOf', 'allOf']) {
    if (schemaMap[keyword] is List) return keyword;
  }
  return '';
}
