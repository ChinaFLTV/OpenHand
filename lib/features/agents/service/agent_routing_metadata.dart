import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../../../shared/util/bounded_json_conversion.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart';
import '../model/agent_models.dart';

const int agentRouteFrontMatterMaxChars = 32768;
const int agentRouteKeywordMaxChars = 256;
const int agentRouteKeywordMaxItems = 128;
const int _agentRouteMaxDepth = 16;
const int _agentRouteMaxContainerItems = 256;
const int _agentRouteMaxTotalNodes = 4096;
const int _agentRoutePreviewMaxChars = 600;
const BoundedJsonConversionConfig _agentRouteConversionConfig =
    BoundedJsonConversionConfig(
      maxDepth: _agentRouteMaxDepth,
      maxContainerItems: _agentRouteMaxContainerItems,
      maxTotalNodes: _agentRouteMaxTotalNodes,
      maxStringCodeUnits: 2048,
      maxDepthPlaceholder: '<层级过深>',
      cyclicMapPlaceholder: '<循环映射>',
      cyclicIterablePlaceholder: '<循环集合>',
      truncatedPlaceholder: aiSessionMessageTruncatedPlaceholder,
    );

class AgentRoutingMetadata {
  const AgentRoutingMetadata({
    required this.frontMatter,
    required this.preview,
    required this.keywords,
    required this.hasRoute,
  });

  factory AgentRoutingMetadata.fromAgent(AgentProfile agent) {
    final raw = agent.routeFrontMatter;
    final frontMatter = parseAgentRouteFrontMatter(raw);
    return AgentRoutingMetadata(
      frontMatter: frontMatter,
      preview: _preview(raw),
      keywords: _routingKeywords(frontMatter, agent),
      hasRoute: raw.trim().isNotEmpty || frontMatter.isNotEmpty,
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
  if (raw.length > agentRouteFrontMatterMaxChars) {
    return const <String, Object?>{};
  }
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
    if (decoded is Map) return _boundedJsonMap(decoded);
  } catch (_) {
    return null;
  }
  return null;
}

Map<String, Object?>? _tryParseYamlMap(String text) {
  if (!text.contains(':')) return null;
  try {
    final decoded = loadYaml(text);
    if (decoded is YamlMap || decoded is Map) {
      return _boundedJsonMap(decoded as Map);
    }
  } catch (_) {
    return null;
  }
  return null;
}

Map<String, Object?> _parseFlatKeyValueLines(String text) {
  final values = <String, Object?>{};
  final lines = const LineSplitter().convert(text);
  for (var i = 0; i < lines.length && i < _agentRouteMaxTotalNodes; i += 1) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separatorIndex = trimmed.indexOf(':');
    if (separatorIndex <= 0) continue;
    final key = trimmed.substring(0, separatorIndex).trim();
    final value = trimmed.substring(separatorIndex + 1).trim();
    if (key.isEmpty || value.isEmpty) continue;
    values[key] = _stripQuotes(value);
    if (values.length > _agentRouteMaxContainerItems) break;
  }
  return _boundedJsonMap(values);
}

Map<String, Object?> _boundedJsonMap(Map<dynamic, dynamic> raw) {
  final converted = convertToJsonSafeMap(
    raw,
    config: _agentRouteConversionConfig,
  );
  final result = <String, Object?>{};
  for (final entry in converted.entries) {
    final key = entry.key.trim();
    if (key.isEmpty) continue;
    result[key] = entry.value;
  }
  return result;
}

List<String> _routingKeywords(
  Map<String, Object?> frontMatter,
  AgentProfile agent,
) {
  return _boundedDistinctStrings(<Object?>[
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
    ])
      frontMatter[key],
    agent.taskLabels,
    agent.skillNames,
  ]);
}

List<String> _boundedDistinctStrings(Iterable<Object?> sources) {
  final result = <String>[];
  final seen = <String>{};

  bool collect(Object? value, int depth) {
    if (value == null || result.length >= agentRouteKeywordMaxItems) {
      return result.length < agentRouteKeywordMaxItems;
    }
    if (value is Iterable) {
      if (depth >= _agentRouteMaxDepth) return true;
      var itemCount = 0;
      for (final item in value) {
        if (itemCount >= _agentRouteMaxContainerItems ||
            !collect(item, depth + 1)) {
          break;
        }
        itemCount += 1;
      }
      return result.length < agentRouteKeywordMaxItems;
    }
    final text = '$value';
    if (text.length > agentRouteFrontMatterMaxChars) return true;
    for (final raw in splitTrimmedNonEmpty(text)) {
      if (raw.length > agentRouteKeywordMaxChars) continue;
      final normalized = raw.toLowerCase();
      if (seen.add(normalized)) result.add(raw);
      if (result.length >= agentRouteKeywordMaxItems) return false;
    }
    return true;
  }

  for (final source in sources) {
    if (!collect(source, 0)) break;
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
  return clipTextByCodeUnits(raw, _agentRoutePreviewMaxChars).trim();
}
