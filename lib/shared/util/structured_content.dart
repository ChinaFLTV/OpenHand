import 'dart:convert';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';
import 'package:yaml/yaml.dart';

import 'bounded_json_conversion.dart';
import 'byte_size_format.dart';

const int kOpenHandJsonTreeMaxCharacters = 512 * kBytesPerKiB;
const int kOpenHandJsonTreeMaxNodes = 4096;
const int kOpenHandJsonTreeMaxDepth = 32;
const int kOpenHandNativeContentMaxCharacters = 64 * kBytesPerKiB;

const openHandContentConversionConfig = BoundedJsonConversionConfig(
  maxDepth: kOpenHandJsonTreeMaxDepth,
  maxContainerItems: kOpenHandJsonTreeMaxNodes,
  maxTotalNodes: kOpenHandJsonTreeMaxNodes + 1,
  maxStringCodeUnits: kOpenHandJsonTreeMaxCharacters,
  maxTotalStringCodeUnits: kOpenHandJsonTreeMaxCharacters,
);

final class OpenHandStructuredContent {
  const OpenHandStructuredContent({this.value, this.language});

  final Object? value;
  final String? language;
}

/// 仅生成阅读视图，不改写原文；格式异常或预算超限时保留语法提示并回退。
OpenHandStructuredContent parseOpenHandStructuredContent(
  String text, {
  String? language,
}) {
  final source = text.trim();
  final hint = language?.trim().toLowerCase();
  final probe = source.length > kOpenHandNativeContentMaxCharacters
      ? source.substring(0, kOpenHandNativeContentMaxCharacters)
      : source;
  final ini =
      RegExp(r'^\s*\[[^\]\r\n]+\]\s*(?:\r?\n|$)').hasMatch(probe) &&
      RegExp(r'^\s*[\w.-]+\s*=', multiLine: true).hasMatch(probe);
  final detected = switch (hint) {
    'plist' || 'xml' => 'xml',
    'yml' || 'yaml' => 'yaml',
    'systemd' || 'ini' => 'ini',
    'shell' || 'sh' || 'zsh' => 'bash',
    '' || null =>
      ini
          ? 'ini'
          : source.startsWith('{') || source.startsWith('[')
          ? 'json'
          : source.startsWith('<')
          ? 'xml'
          : RegExp(
              r'^(?:---\s*$|\s*[^\s:#][^\r\n]*:\s|\s*-\s)',
              multiLine: true,
            ).hasMatch(probe)
          ? 'yaml'
          : null,
    _ => hint,
  };
  final fallback = OpenHandStructuredContent(language: detected);
  if (source.isEmpty || source.length > kOpenHandJsonTreeMaxCharacters) {
    return fallback;
  }
  try {
    Object? value;
    switch (detected) {
      case 'json':
        value = decodeJsonTextUsingConfig(
          source,
          maxTextCodeUnits: kOpenHandJsonTreeMaxCharacters,
          config: openHandContentConversionConfig,
        );
      case 'xml':
        final document = tryParseBoundedOpenHandXml(source);
        if (document == null) return fallback;
        final root = document.rootElement;
        if (root.name.qualified == 'plist') {
          final children = root.childElements.toList();
          if (children.length != 1) return fallback;
          value = _plistValue(children.single);
        } else {
          value = {root.name.qualified: _xmlValue(root)};
        }
      case 'ini':
        if (source.length > kOpenHandNativeContentMaxCharacters) {
          return fallback;
        }
        value = _iniValue(source);
      case 'yaml':
        if (source.length > kOpenHandNativeContentMaxCharacters ||
            !_boundedYaml(source)) {
          return fallback;
        }
        value = loadYaml(source);
      default:
        return fallback;
    }
    if ((value is! Map && value is! List) ||
        measureJsonValueWithinBounds(
              value,
              maxDepth: kOpenHandJsonTreeMaxDepth,
              maxContainerItems: kOpenHandJsonTreeMaxNodes,
              maxTotalNodes: kOpenHandJsonTreeMaxNodes + 1,
              maxStringCodeUnits: kOpenHandJsonTreeMaxCharacters,
              maxTotalStringCodeUnits: kOpenHandJsonTreeMaxCharacters,
            ) ==
            null) {
      return fallback;
    }
    return OpenHandStructuredContent(value: value, language: detected);
  } on FormatException {
    return fallback;
  }
}

/// 在构造 XML 文档前检查节点与深度预算，不解析外部实体。
XmlDocument? tryParseBoundedOpenHandXml(String source) {
  if (source.length > kOpenHandNativeContentMaxCharacters) return null;
  try {
    var depth = 0;
    var nodes = 0;
    for (final event in parseEvents(
      source,
      validateNesting: true,
      validateDocument: true,
    )) {
      nodes += 1;
      if (event is XmlStartElementEvent) {
        nodes += event.attributes.length;
        if (depth + 1 > kOpenHandJsonTreeMaxDepth) return null;
        if (!event.isSelfClosing) depth += 1;
      } else if (event is XmlEndElementEvent) {
        depth -= 1;
      }
      if (nodes > kOpenHandJsonTreeMaxNodes) return null;
    }
    return XmlDocument.parse(source);
  } on FormatException {
    return null;
  }
}

Object _plistValue(XmlElement element) {
  final children = element.childElements.toList();
  final kind = element.name.qualified;
  if (kind != 'dict' && kind != 'array' && children.isNotEmpty) {
    throw const FormatException('属性列表标量包含嵌套字段。');
  }
  switch (kind) {
    case 'dict':
      if (children.length.isOdd) throw const FormatException('属性列表字段不完整。');
      final values = <String, Object>{};
      for (var index = 0; index < children.length; index += 2) {
        final key = children[index];
        if (key.name.qualified != 'key' || values.containsKey(key.innerText)) {
          throw const FormatException('属性列表字段名称无效或重复。');
        }
        values[key.innerText] = _plistValue(children[index + 1]);
      }
      return values;
    case 'array':
      return children.map(_plistValue).toList();
    case 'true':
    case 'false':
      if (children.isNotEmpty || element.innerText.trim().isNotEmpty) {
        throw const FormatException('属性列表布尔值格式无效。');
      }
      return element.name.qualified == 'true';
    case 'string':
      if (children.isNotEmpty) throw const FormatException('属性列表字符串格式无效。');
      return element.innerText;
    case 'integer':
      final text = element.innerText.trim();
      if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(text)) {
        throw const FormatException('属性列表整数格式无效。');
      }
      if (text.length > 16) return element.innerText;
      final number = BigInt.tryParse(text);
      if (number == null) throw const FormatException('属性列表整数格式无效。');
      // 超出跨平台安全整数范围时保留文本，避免丢失精度。
      return number.abs() <= BigInt.from(9007199254740991)
          ? number.toInt()
          : element.innerText;
    case 'real':
      final number = double.tryParse(element.innerText.trim());
      if (number == null || !number.isFinite) {
        throw const FormatException('属性列表数值格式无效。');
      }
      return number;
    case 'date':
    case 'data':
      return {element.name.qualified: element.innerText};
    default:
      throw const FormatException('属性列表字段类型暂不支持。');
  }
}

Object _xmlValue(XmlElement element) {
  final children = element.childElements.toList();
  final attributes = <String, Object>{
    for (final attribute in element.attributes)
      '@${attribute.name.qualified}': attribute.value,
  };
  if (children.isEmpty) {
    return attributes.isEmpty
        ? element.innerText
        : {...attributes, '#text': element.innerText};
  }
  final mixed = element.children.any(
    (node) =>
        (node is XmlText || node is XmlCDATA) && node.value!.trim().isNotEmpty,
  );
  if (mixed) {
    return {
      ...attributes,
      '#content': [
        for (final node in element.children)
          if (node is XmlElement)
            {node.name.qualified: _xmlValue(node)}
          else if (node is XmlText || node is XmlCDATA)
            node.value!,
      ],
    };
  }
  final groups = <String, List<Object>>{};
  for (final child in children) {
    (groups[child.name.qualified] ??= []).add(_xmlValue(child));
  }
  return {
    ...attributes,
    for (final entry in groups.entries)
      entry.key: entry.value.length == 1 ? entry.value.single : entry.value,
  };
}

bool _boundedYaml(String source) {
  // 别名可能放大节点数量或形成循环，阅读视图直接保留原文。
  if (RegExp(r'(^|[\s\[\]{},:])[&*][\w-]+').hasMatch(source)) return false;
  final indents = <int>[];
  var lines = 0;
  var flowDepth = 0;
  for (final line in const LineSplitter().convert(source)) {
    if (++lines > kOpenHandJsonTreeMaxNodes) return false;
    final content = line.trimLeft();
    if (content.isEmpty || content.startsWith('#')) continue;
    final indent = line.length - content.length;
    while (indents.isNotEmpty && indents.last > indent) {
      indents.removeLast();
    }
    if (indents.isEmpty || indents.last < indent) indents.add(indent);
    if (indents.length > kOpenHandJsonTreeMaxDepth) return false;
    // 保守限制流式容器；字符串中的括号超限时也仅回退原文。
    for (final unit in content.codeUnits) {
      if (unit == 0x5b || unit == 0x7b) {
        if (++flowDepth > kOpenHandJsonTreeMaxDepth) return false;
      } else if (unit == 0x5d || unit == 0x7d) {
        if (flowDepth > 0) flowDepth -= 1;
      }
    }
  }
  return true;
}

Map<String, Object?>? _iniValue(String source) {
  final values = <String, Object?>{};
  var section = values;
  var lines = 0;
  for (final line in const LineSplitter().convert(source)) {
    if (++lines > kOpenHandJsonTreeMaxNodes) return null;
    final text = line.trim();
    if (text.isEmpty || text.startsWith('#') || text.startsWith(';')) continue;
    // 续行和扩展语法保留原文，避免改变运行时解释方式。
    if (text.endsWith(r'\')) return null;
    if (text.startsWith('[') && text.endsWith(']')) {
      final name = text.substring(1, text.length - 1);
      if (name.isEmpty) return null;
      final previous = values[name];
      if (previous != null && previous is! Map<String, Object?>) return null;
      section = previous as Map<String, Object?>? ?? <String, Object?>{};
      values[name] = section;
      continue;
    }
    final separator = line.indexOf('=');
    if (separator <= 0) return null;
    final key = line.substring(0, separator).trim();
    if (key.isEmpty) return null;
    final value = line.substring(separator + 1);
    final previous = section[key];
    if (previous is Map) return null;
    if (previous is List<Object?>) {
      previous.add(value);
    } else {
      section[key] = previous == null ? value : [previous, value];
    }
  }
  return values.isEmpty ? null : values;
}
