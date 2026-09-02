import 'dart:collection';
import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import '../util/byte_size_format.dart';
import '../util/input_value_parsing.dart';
import 'markdown_math.dart';

final RegExp _markdownSetextEscapePattern = RegExp(
  r'(^|\n)(\s*)(=+|\^+)(?=\n|$)',
);
final RegExp _markdownInlineFencedBlockLinePattern = RegExp(
  r'^( {0,3})(`{3,}|~{3,})([^\n]*)$',
);
final RegExp _markdownFenceInfoTokenPattern = RegExp(
  r'^([A-Za-z0-9_+#\.-]+)(?:\s+|$)',
);
final RegExp _markdownToolScaffoldingLinePattern = RegExp(
  r'^\s*(?:'
  r'tool\s*:\s*\w[\w\-\.]*'
  r'|工具\s*[:：]\s*\w[\w\-\.]*'
  r'|工具调用\s*[:：].*'
  r'|\[?tool_call\]?\s*[:：]?\s*.*'
  r'|function_calls?\s*[:：].*'
  r'|<?function_calls?>?\s*$'
  r'|</?invoke[^>]*>\s*$'
  r')\s*$',
  caseSensitive: false,
  multiLine: true,
);

/// 统一规范化 Markdown 源码；线程消息可额外清理结构化工具调用脚手架。
String normalizeOpenHandMarkdownSource(
  String source, {
  bool stripMessageScaffolding = false,
}) {
  return _markdownSourceCache.resolve(
    source,
    stripMessageScaffolding: stripMessageScaffolding,
  );
}

/// 移除文档开头的 YAML front matter，未闭合时保留原文。
String stripOpenHandMarkdownFrontMatter(String source) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = const LineSplitter().convert(normalized);
  if (lines.isEmpty || lines.first.replaceFirst('\ufeff', '').trim() != '---') {
    return normalized;
  }
  for (var index = 1; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line != '---' && line != '...') continue;
    var bodyStart = index + 1;
    while (bodyStart < lines.length && lines[bodyStart].trim().isEmpty) {
      bodyStart += 1;
    }
    return lines.skip(bodyStart).join('\n');
  }
  return normalized;
}

class _MarkdownSourceCache {
  static const int _maxEntries = 256;
  static const int _maxEntryChars = 256 * kBytesPerKiB;
  static const int _maxTotalChars = 2 * kBytesPerMiB;

  final LinkedHashMap<(String, bool), String> _entries =
      LinkedHashMap<(String, bool), String>();
  int _chars = 0;

  String resolve(String source, {required bool stripMessageScaffolding}) {
    final key = (source, stripMessageScaffolding);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final normalizedFences = _normalizeInlineFencedCodeBlocks(normalized);
    final effectiveSource = stripMessageScaffolding
        ? _stripToolScaffoldingFromMarkdown(normalizedFences)
        : normalizedFences;
    final value = _closeUnterminatedFencedCodeBlock(effectiveSource)
        .replaceAllMapped(
          _markdownSetextEscapePattern,
          (match) => '${match[1]}${match[2]}\\${match[3]}',
        );
    if (source.length > _maxEntryChars) return value;
    _entries[key] = value;
    _chars += source.length + value.length;
    while (_entries.length > _maxEntries || _chars > _maxTotalChars) {
      final oldestKey = _entries.keys.first;
      final removed = _entries.remove(oldestKey);
      if (removed == null) break;
      _chars -= oldestKey.$1.length + removed.length;
    }
    return value;
  }
}

final _MarkdownSourceCache _markdownSourceCache = _MarkdownSourceCache();

String _normalizeInlineFencedCodeBlocks(String source) {
  if (source.isEmpty || !source.contains('```') && !source.contains('~~~')) {
    return source;
  }
  final lines = source.split('\n');
  var changed = false;
  final normalizedLines = <String>[];
  for (final line in lines) {
    final match = _markdownInlineFencedBlockLinePattern.firstMatch(line);
    if (match == null) {
      normalizedLines.add(line);
      continue;
    }
    final indent = match.group(1)!;
    final fence = match.group(2)!;
    final afterFence = match.group(3)!;
    final closingIndex = afterFence.lastIndexOf(fence);
    if (closingIndex <= 0) {
      normalizedLines.add(line);
      continue;
    }
    final inlineSegment = afterFence.substring(0, closingIndex).trimLeft();
    final trailingSegment = afterFence.substring(closingIndex + fence.length);
    if (inlineSegment.isEmpty) {
      normalizedLines.add(line);
      continue;
    }
    var openingFence = '$indent$fence';
    var codeBody = inlineSegment;
    final infoMatch = _markdownFenceInfoTokenPattern.firstMatch(inlineSegment);
    if (infoMatch != null) {
      final infoToken = infoMatch.group(1)!;
      final remainder = inlineSegment.substring(infoMatch.end).trimLeft();
      if (remainder.isNotEmpty) {
        openingFence = '$openingFence$infoToken';
        codeBody = remainder;
      }
    }
    if (codeBody.trim().isEmpty) {
      normalizedLines.add(line);
      continue;
    }
    changed = true;
    normalizedLines
      ..add(openingFence)
      ..add(codeBody.trimRight())
      ..add('$indent$fence');
    final trailing = trailingSegment.trimLeft();
    if (trailing.isNotEmpty) normalizedLines.add(trailing);
  }
  return changed ? normalizedLines.join('\n') : source;
}

String _stripToolScaffoldingFromMarkdown(String source) {
  if (!_markdownToolScaffoldingLinePattern.hasMatch(source)) return source;
  final lines = source.split('\n');
  final buffer = StringBuffer();
  var inFence = false;
  String? fenceMarker;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    if (inFence) {
      if (fenceMarker != null && trimmed.startsWith(fenceMarker)) {
        inFence = false;
        fenceMarker = null;
      }
    } else if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = true;
      fenceMarker = trimmed.startsWith('```') ? '```' : '~~~';
    } else if (_markdownToolScaffoldingLinePattern.hasMatch(line)) {
      continue;
    }
    buffer.write(line);
    if (index != lines.length - 1) buffer.write('\n');
  }
  return buffer.toString();
}

String _closeUnterminatedFencedCodeBlock(String source) {
  final fencePattern = RegExp(r'^[ ]{0,3}((`{3,}|~{3,}))[^\n]*$');
  String? openFence;
  String? openFenceMarker;
  for (final line in const LineSplitter().convert(source)) {
    final match = fencePattern.firstMatch(line);
    if (match == null) continue;
    final delimiter = match.group(1)!;
    final marker = delimiter[0];
    if (openFence == null) {
      openFence = delimiter;
      openFenceMarker = marker;
    } else if (marker == openFenceMarker &&
        delimiter.length >= openFence.length) {
      openFence = null;
      openFenceMarker = null;
    }
  }
  if (openFence == null) return source;
  final separator = source.isEmpty || source.endsWith('\n') ? '' : '\n';
  return '$source$separator$openFence';
}

/// 按 OpenHand 的扩展集解析 Markdown，并就地做 AST 清洗。
///
/// 主会话正文、Harness 面板、流式渲染各写一遍同一份 Document 配置：扩展集或
/// 数学语法只改一处，同一段内容在几个视图里的渲染就会分叉。
///
/// [blockSyntaxes] 默认带上数学块；流式快渲通道不解析数学，传空表即可。
List<md.Node> parseOpenHandMarkdown(
  String source, {
  required List<md.InlineSyntax> inlineSyntaxes,
  List<md.BlockSyntax>? blockSyntaxes,
}) {
  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    blockSyntaxes: blockSyntaxes ?? openHandMarkdownMathBlockSyntaxes,
    inlineSyntaxes: inlineSyntaxes,
    encodeHtml: false,
  );
  final nodes = document.parseLines(const LineSplitter().convert(source));
  sanitizeOpenHandMarkdownAst(nodes);
  return nodes;
}

/// 就地规范化 Markdown AST 中有序列表的 `start` 属性。
///
/// 模型输出里常见 `start="01"`、`start=""` 这类取值；渲染层会直接把字符串
/// 丢给 int 解析，抛出后整段消息退化成纯文本。这里把非法值摘掉、合法值归一
/// 成十进制字符串。主会话与 Harness 的 Markdown 渲染此前各写了一份同样的
/// 递归实现。
void sanitizeOpenHandMarkdownAst(List<md.Node> nodes) {
  for (final node in nodes) {
    if (node is! md.Element) continue;
    final attributes = node.attributes;
    if (node.tag == 'ol') {
      final startValue = optionalIntFromValue(attributes['start']);
      if (startValue == null) {
        attributes.remove('start');
      } else {
        attributes['start'] = startValue.toString();
      }
    }
    final children = node.children;
    if (children != null && children.isNotEmpty) {
      sanitizeOpenHandMarkdownAst(children);
    }
  }
}
