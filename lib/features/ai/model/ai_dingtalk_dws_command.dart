import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/text_normalization.dart';

String dingtalkDwsToolName(
  AiDingTalkDwsCommand command, {
  Set<String>? usedNames,
}) {
  final slug = collapseRepeatedUnderscores(
    command.cliPath.replaceAll(RegExp('[^A-Za-z0-9]+'), '_'),
  ).replaceAll(RegExp(r'^_|_$'), '');
  final base = 'DingTalkDws_${slug.isEmpty ? 'Command' : slug}';
  if (usedNames == null || usedNames.add(base)) return base;
  var suffix = 2;
  while (!usedNames.add('${base}_$suffix')) {
    suffix += 1;
  }
  return '${base}_$suffix';
}

/// DWS CLI 的安全命令描述。设置仅保存 [cliPath]，完整参数来自运行时目录。
class AiDingTalkDwsCommand {
  const AiDingTalkDwsCommand({
    required this.productId,
    required this.productName,
    required this.cliPath,
    required this.name,
    required this.description,
    this.summary = '',
    this.effect = 'read',
    this.risk = 'low',
    this.confirmation = 'not_required',
    this.parameters = const <String, Object?>{},
    this.positionals = const <String>[],
    this.examples = const <String>[],
  });

  factory AiDingTalkDwsCommand.fromJson(Map<String, Object?> json) {
    final cliPath = stringFromValue(json['cli_path']).trim();
    final name = stringFromValue(json['name']).trim();
    if (cliPath.isEmpty || name.isEmpty) {
      throw const FormatException('DWS 命令标识不完整。');
    }
    final rawParameters = json['parameters'];
    final parameters = <String, Object?>{};
    if (rawParameters is Map) {
      for (final entry in rawParameters.entries.take(128)) {
        final key = '${entry.key}'.trim();
        if (key.isEmpty || entry.value is! Map) continue;
        parameters[key] = _safeParameterSchema(entry.value);
      }
    }
    final positionals = <String>[];
    final rawPositionals = json['positionals'];
    if (rawPositionals is List) {
      for (final item in rawPositionals.take(16)) {
        final positional = item is Map ? stringKeyedMapFromValue(item) : null;
        final positionalName = positional == null
            ? '$item'.trim()
            : stringFromValue(positional['name']).trim();
        if (positionalName.isEmpty || positionals.contains(positionalName)) {
          continue;
        }
        positionals.add(positionalName);
        final schema = positional == null
            ? <String, Object?>{'type': 'string'}
            : _safeParameterSchema(positional);
        parameters.putIfAbsent(positionalName, () => schema);
      }
    }
    return AiDingTalkDwsCommand(
      productId: stringFromValue(json['product_id']).trim(),
      productName: stringFromValue(json['product_name']).trim(),
      cliPath: cliPath,
      name: name,
      description: _clip(stringFromValue(json['description']), 400),
      summary: _clip(stringFromValue(json['summary']), 400),
      effect: _clip(stringFromValue(json['effect']), 32),
      risk: _clip(stringFromValue(json['risk']), 32),
      confirmation: _clip(stringFromValue(json['confirmation']), 32),
      parameters: Map<String, Object?>.unmodifiable(parameters),
      positionals: positionals.toList(growable: false),
      examples: _stringList(json['examples'], 8, maxLength: 800),
    );
  }

  final String productId;
  final String productName;
  final String cliPath;
  final String name;
  final String description;
  final String summary;
  final String effect;
  final String risk;
  final String confirmation;
  final Map<String, Object?> parameters;
  final List<String> positionals;
  final List<String> examples;

  String get id => cliPath;

  List<String> get requiredParameterNames => parameters.entries
      .where(
        (entry) =>
            entry.value is Map && (entry.value as Map)['required'] == true,
      )
      .map((entry) => entry.key)
      .toList(growable: false);

  Map<String, Object?> toJson() => <String, Object?>{
    'product_id': productId,
    'product_name': productName,
    'cli_path': cliPath,
    'name': name,
    'description': description,
    'summary': summary,
    'effect': effect,
    'risk': risk,
    'confirmation': confirmation,
    'parameters': parameters,
    'positionals': positionals,
    'examples': examples,
  };

  static Map<String, Object?> _safeParameterSchema(Object value) {
    final source = stringKeyedMapFromValue(value);
    final type = stringFromValue(source['type']).trim().toLowerCase();
    final normalizedType =
        const <String>{
          'string',
          'number',
          'integer',
          'boolean',
          'array',
          'object',
        }.contains(type)
        ? type
        : 'string';
    final result = <String, Object?>{'type': normalizedType};
    final description = _clip(stringFromValue(source['description']), 300);
    if (description.isNotEmpty) result['description'] = description;
    if (boolFromValue(source['required'])) result['required'] = true;
    if (source['enum'] is List) {
      result['enum'] = (source['enum'] as List)
          .take(32)
          .toList(growable: false);
    }
    if (normalizedType == 'array') {
      result['items'] = <String, Object?>{'type': 'string'};
    }
    return result;
  }

  static List<String> _stringList(
    Object? value,
    int limit, {
    int maxLength = 300,
  }) {
    if (value is! List) return const <String>[];
    final seen = <String>{};
    final result = <String>[];
    for (final item in value) {
      final text = _clip('$item', maxLength).trim();
      if (text.isNotEmpty && seen.add(text)) result.add(text);
      if (result.length >= limit) break;
    }
    return result.toList(growable: false);
  }

  static String _clip(String value, int maxLength) {
    final text = value.trim();
    return clipTextByCodeUnits(text, maxLength, suffix: '…');
  }
}
