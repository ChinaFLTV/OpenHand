import 'dart:convert';

import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

import 'input_value_parsing.dart';

enum StructuredTextFormat { json, xml, yaml }

const int _kMaxStructuredTextNestingDepth = 64;
const String _kCircularStructuredValuePlaceholder = '<circular>';
const String _kMaxDepthStructuredValuePlaceholder = '<max-depth>';

final class StructuredTextFormatResult {
  const StructuredTextFormatResult({required this.text, this.format});

  factory StructuredTextFormatResult.fromMap(Map<String, Object?> map) {
    final formatName = map['format'];
    return StructuredTextFormatResult(
      text: '${map['text'] ?? ''}',
      format: formatName is String ? _formatFromName(formatName) : null,
    );
  }

  final String text;
  final StructuredTextFormat? format;

  Map<String, Object?> toMap() {
    return <String, Object?>{'text': text, 'format': format?.name};
  }
}

StructuredTextFormat? _formatFromName(String name) {
  return enumByName(
    StructuredTextFormat.values,
    name,
    normalize: (value) => value.toLowerCase(),
  );
}

String structuredTextFormatLabel(StructuredTextFormat format) {
  return switch (format) {
    StructuredTextFormat.json => 'JSON',
    StructuredTextFormat.xml => 'XML',
    StructuredTextFormat.yaml => 'YAML',
  };
}

StructuredTextFormatResult formatStructuredTextForDisplay(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return StructuredTextFormatResult(text: trimmed);
  }
  for (final strategy in _formatStrategies) {
    final formatted = strategy.tryFormat(trimmed);
    if (formatted != null) return formatted;
  }
  return StructuredTextFormatResult(text: trimmed);
}

const List<_StructuredTextFormatterStrategy> _formatStrategies =
    <_StructuredTextFormatterStrategy>[
      _JsonTextFormatterStrategy(),
      _XmlTextFormatterStrategy(),
      _YamlTextFormatterStrategy(),
    ];

abstract interface class _StructuredTextFormatterStrategy {
  StructuredTextFormatResult? tryFormat(String trimmed);
}

final class _JsonTextFormatterStrategy
    implements _StructuredTextFormatterStrategy {
  const _JsonTextFormatterStrategy();

  @override
  StructuredTextFormatResult? tryFormat(String trimmed) {
    if (!_looksLikeJson(trimmed)) return null;
    try {
      final decoded = jsonDecode(trimmed);
      return StructuredTextFormatResult(
        text: prettyPrintJson(decoded),
        format: StructuredTextFormat.json,
      );
    } catch (_) {
      return null;
    }
  }
}

final class _XmlTextFormatterStrategy
    implements _StructuredTextFormatterStrategy {
  const _XmlTextFormatterStrategy();

  @override
  StructuredTextFormatResult? tryFormat(String trimmed) {
    if (!trimmed.startsWith('<')) return null;
    try {
      final document = XmlDocument.parse(trimmed);
      return StructuredTextFormatResult(
        text: document.toXmlString(pretty: true, indent: '  '),
        format: StructuredTextFormat.xml,
      );
    } catch (_) {
      return null;
    }
  }
}

final class _YamlTextFormatterStrategy
    implements _StructuredTextFormatterStrategy {
  const _YamlTextFormatterStrategy();

  @override
  StructuredTextFormatResult? tryFormat(String trimmed) {
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) return null;
    if (!_looksLikeYaml(trimmed)) return null;
    try {
      final loaded = loadYaml(trimmed);
      if (loaded is! Map && loaded is! List) return null;
      return StructuredTextFormatResult(
        text: prettyPrintJson(_jsonSafeValue(loaded)),
        format: StructuredTextFormat.yaml,
      );
    } catch (_) {
      return null;
    }
  }
}

bool _looksLikeJson(String trimmed) {
  if (trimmed.length < 2) return false;
  return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
      (trimmed.startsWith('[') && trimmed.endsWith(']'));
}

bool _looksLikeYaml(String trimmed) {
  final lines = const LineSplitter()
      .convert(trimmed)
      .map((line) => line.trimLeft())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .take(12);
  var structuredLineCount = 0;
  for (final line in lines) {
    if (line == '---' || line == '...' || line.startsWith('- ')) {
      structuredLineCount += 1;
      continue;
    }
    final colonIndex = line.indexOf(':');
    if (colonIndex > 0) structuredLineCount += 1;
  }
  return structuredLineCount > 0;
}

Object? _jsonSafeValue(Object? value) {
  return _jsonSafeValueInternal(value, depth: 0, seen: Set<Object>.identity());
}

Object? _jsonSafeValueInternal(
  Object? value, {
  required int depth,
  required Set<Object> seen,
}) {
  if (value == null || value is String || value is bool) {
    return value;
  }
  if (value is num) return value.isFinite ? value : value.toString();
  if (depth >= _kMaxStructuredTextNestingDepth) {
    return _kMaxDepthStructuredValuePlaceholder;
  }
  if (value is YamlMap || value is Map) {
    if (!seen.add(value)) return _kCircularStructuredValuePlaceholder;
    final map = value as Map;
    try {
      return <String, Object?>{
        for (final entry in map.entries)
          '${entry.key}': _jsonSafeValueInternal(
            entry.value,
            depth: depth + 1,
            seen: seen,
          ),
      };
    } finally {
      seen.remove(value);
    }
  }
  if (value is YamlList || value is List) {
    if (!seen.add(value)) return _kCircularStructuredValuePlaceholder;
    final list = value as List;
    try {
      return list
          .map(
            (entry) =>
                _jsonSafeValueInternal(entry, depth: depth + 1, seen: seen),
          )
          .toList(growable: false);
    } finally {
      seen.remove(value);
    }
  }
  return value.toString();
}
