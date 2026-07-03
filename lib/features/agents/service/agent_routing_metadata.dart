import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../../../shared/util/input_value_parsing.dart';
import '../model/agent_models.dart';

class AgentRoutingMetadata {
  const AgentRoutingMetadata({
    required this.frontMatter,
    required this.preview,
    required this.keywords,
    required this.hasRoute,
  });

  factory AgentRoutingMetadata.fromAgent(AgentProfile agent) {
    final raw = agent.routeFrontMatter.trim();
    final frontMatter = parseAgentRouteFrontMatter(raw);
    return AgentRoutingMetadata(
      frontMatter: frontMatter,
      preview: _preview(raw),
      keywords: _routingKeywords(frontMatter, agent),
      hasRoute: raw.isNotEmpty || frontMatter.isNotEmpty,
    );
  }

  final Map<String, Object?> frontMatter;
  final String preview;
  final List<String> keywords;
  final bool hasRoute;

  Map<String, Object?> toJson({bool includeRawPreview = true}) {
    return <String, Object?>{
      'has_route': hasRoute,
      if (frontMatter.isNotEmpty) 'front_matter': frontMatter,
      if (keywords.isNotEmpty) 'keywords': keywords,
      if (includeRawPreview && preview.isNotEmpty) 'raw_preview': preview,
    };
  }
}

Map<String, Object?> parseAgentRouteFrontMatter(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const <String, Object?>{};
  final candidate = _frontMatterBody(trimmed) ?? trimmed;
  final json = _tryParseJsonMap(candidate);
  if (json != null) return json;
  final yaml = _tryParseYamlMap(candidate);
  if (yaml != null) return yaml;
  return _parseFlatKeyValueLines(candidate);
}

String? _frontMatterBody(String trimmed) {
  final lines = const LineSplitter().convert(trimmed);
  if (lines.isEmpty || lines.first.trim() != '---') return null;
  final body = <String>[];
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim() == '---') return body.join('\n').trim();
    body.add(line);
  }
  return null;
}

Map<String, Object?>? _tryParseJsonMap(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) return _jsonMap(decoded);
  } catch (_) {
    return null;
  }
  return null;
}

Map<String, Object?>? _tryParseYamlMap(String text) {
  if (!text.contains(':')) return null;
  try {
    final decoded = loadYaml(text);
    if (decoded is YamlMap || decoded is Map) return _jsonMap(decoded as Map);
  } catch (_) {
    return null;
  }
  return null;
}

Map<String, Object?> _parseFlatKeyValueLines(String text) {
  final values = <String, Object?>{};
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separatorIndex = trimmed.indexOf(':');
    if (separatorIndex <= 0) continue;
    final key = trimmed.substring(0, separatorIndex).trim();
    final value = trimmed.substring(separatorIndex + 1).trim();
    if (key.isEmpty || value.isEmpty) continue;
    values[key] = _stripQuotes(value);
  }
  return values;
}

Map<String, Object?> _jsonMap(Map<dynamic, dynamic> raw) {
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = '${entry.key}'.trim();
    if (key.isEmpty) continue;
    result[key] = _jsonValue(entry.value);
  }
  return result;
}

Object? _jsonValue(Object? raw) {
  if (raw == null || raw is num || raw is bool || raw is String) return raw;
  if (raw is YamlList || raw is List) {
    return (raw as Iterable).map(_jsonValue).toList(growable: false);
  }
  if (raw is YamlMap || raw is Map) return _jsonMap(raw as Map);
  return '$raw';
}

List<String> _routingKeywords(
  Map<String, Object?> frontMatter,
  AgentProfile agent,
) {
  final values = <String>[];
  for (final key in const <String>[
    'keywords',
    'keyword',
    'triggers',
    'trigger',
    'tags',
    'domains',
    'domain',
    'routes',
    'route',
    'intents',
    'intent',
  ]) {
    values.addAll(_stringsFromValue(frontMatter[key]));
  }
  values.addAll(agent.taskLabels);
  values.addAll(agent.skillNames);
  return _dedupe(values);
}

List<String> _stringsFromValue(Object? raw) {
  if (raw == null) return const <String>[];
  if (raw is Iterable) {
    return raw.expand(_stringsFromValue).toList(growable: false);
  }
  return splitTrimmedNonEmpty('$raw');
}

List<String> _dedupe(List<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    if (seen.add(value.toLowerCase())) result.add(value);
  }
  return result;
}

String _stripQuotes(String value) {
  if (value.length < 2) return value;
  final first = value.codeUnitAt(0);
  final last = value.codeUnitAt(value.length - 1);
  if ((first == 0x22 && last == 0x22) || (first == 0x27 && last == 0x27)) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

String _preview(String raw) {
  const maxChars = 600;
  final normalized = raw.trim();
  if (normalized.length <= maxChars) return normalized;
  return '${normalized.substring(0, maxChars)}...';
}
