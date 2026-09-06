import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

final RegExp _markdownFencePattern = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
final RegExp _markdownTableDividerCellPattern = RegExp(r'^:?-+:?$');
final RegExp _markdownBacktickRunPattern = RegExp('`+');

/// 用单层 Markdown 斜体标记区分思考消息；已带斜体标记时保持幂等。
String wrapDingTalkThinkingMarkdown(String source) {
  final content = source.trim();
  if (content.isEmpty ||
      _hasOuterEmphasis(content, '*') ||
      _hasOuterEmphasis(content, '_')) {
    return content;
  }
  final marker = !content.startsWith('*') && !content.endsWith('*') ? '*' : '_';
  return '$marker$content$marker';
}

/// 渲染多段思考内容时移除消息级标记，由卡片统一应用斜体样式。
String unwrapDingTalkThinkingMarkdown(String source) {
  final content = source.trim();
  if (dingTalkMarkdownOuterEmphasisMarker(content) != null) {
    return content.substring(1, content.length - 1);
  }
  return content;
}

String? dingTalkMarkdownOuterEmphasisMarker(String source) {
  if (_hasOuterEmphasis(source, '*')) return '*';
  if (_hasOuterEmphasis(source, '_')) return '_';
  return null;
}

bool _hasOuterEmphasis(String source, String marker) {
  if (source.length < 3 ||
      !source.startsWith(marker) ||
      !source.endsWith(marker)) {
    return false;
  }
  return !source.startsWith('$marker$marker') &&
      !source.endsWith('$marker$marker');
}

/// 将 GFM 表格转换为钉钉可稳定显示的键值行，其余 Markdown 保持不变。
String convertDingTalkMarkdownTables(String source) {
  if (!source.contains('|') || !source.contains('-')) return source;
  final trimmed = source.trim();
  final outerEmphasis = dingTalkMarkdownOuterEmphasisMarker(trimmed);
  final content = outerEmphasis == null
      ? source
      : trimmed.substring(1, trimmed.length - 1);
  final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final output = <String>[];
  String? activeFence;

  for (var index = 0; index < lines.length;) {
    final line = lines[index];
    final fence = _markdownFencePattern.firstMatch(line)?.group(1);
    if (fence != null) {
      if (activeFence == null) {
        activeFence = fence;
      } else if (fence.codeUnitAt(0) == activeFence.codeUnitAt(0) &&
          fence.length >= activeFence.length) {
        activeFence = null;
      }
      output.add(line);
      index += 1;
      continue;
    }
    if (activeFence != null ||
        index + 1 >= lines.length ||
        !line.contains('|') ||
        !_isTableDivider(lines[index + 1])) {
      output.add(line);
      index += 1;
      continue;
    }

    var end = index + 2;
    while (end < lines.length &&
        lines[end].trim().isNotEmpty &&
        lines[end].contains('|')) {
      end += 1;
    }
    final candidate = lines.sublist(index, end).join('\n');
    final List<md.Node> nodes;
    try {
      nodes = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      ).parseLines(const LineSplitter().convert(candidate));
    } catch (_) {
      output.add(line);
      index += 1;
      continue;
    }
    final table = nodes.length == 1 && nodes.single is md.Element
        ? nodes.single as md.Element
        : null;
    if (table?.tag != 'table') {
      output.add(line);
      index += 1;
      continue;
    }
    output.addAll(_tablePlainTextLines(table!));
    index = end;
  }
  final converted = output.join('\n');
  return outerEmphasis == null
      ? converted
      : '$outerEmphasis$converted$outerEmphasis';
}

bool _isTableDivider(String line) {
  var normalized = line.trim();
  if (normalized.startsWith('|')) normalized = normalized.substring(1);
  if (normalized.endsWith('|')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final cells = normalized.split('|');
  return cells.isNotEmpty &&
      cells.every(
        (cell) => _markdownTableDividerCellPattern.hasMatch(cell.trim()),
      );
}

List<String> _tablePlainTextLines(md.Element table) {
  final rows = <List<String>>[];
  for (final section
      in table.children?.whereType<md.Element>() ?? const <md.Element>[]) {
    final sectionChildren = section.children;
    if (sectionChildren == null) continue;
    for (final row in sectionChildren.whereType<md.Element>()) {
      if (row.tag != 'tr') continue;
      rows.add(<String>[
        for (final cell
            in row.children?.whereType<md.Element>() ?? const <md.Element>[])
          _inlineMarkdown(cell).trim(),
      ]);
    }
  }
  if (rows.isEmpty) return const <String>[];
  final headers = rows.first;
  final body = rows.skip(1);
  if (headers.length == 2) {
    return <String>[
      for (final row in body)
        '${row.isNotEmpty && row.first.isNotEmpty ? row.first : headers.first}：'
            '${row.length > 1 ? row[1] : ''}',
      if (body.isEmpty) '${headers.first}：${headers.last}',
    ];
  }
  return <String>[
    for (final row in body)
      <String>[
        for (var index = 0; index < headers.length; index++)
          '${headers[index]}：${index < row.length ? row[index] : ''}',
      ].join('；'),
    if (body.isEmpty) headers.join(' | '),
  ];
}

String _inlineMarkdown(md.Node node) {
  if (node is md.Text) return node.text;
  if (node is! md.Element) return node.textContent;
  final text = (node.children ?? const <md.Node>[]).map(_inlineMarkdown).join();
  return switch (node.tag) {
    'strong' => '**$text**',
    'em' => '*$text*',
    'del' => '~~$text~~',
    'code' => _inlineCode(text),
    'a' =>
      node.attributes['href']?.trim().isNotEmpty == true
          ? '[$text](${node.attributes['href']})'
          : text,
    'img' =>
      node.attributes['src']?.trim().isNotEmpty == true
          ? '[$text](${node.attributes['src']})'
          : text,
    'br' => '\n',
    _ => text,
  };
}

String _inlineCode(String text) {
  var fenceLength = 1;
  for (final match in _markdownBacktickRunPattern.allMatches(text)) {
    final length = match.end - match.start + 1;
    if (length > fenceLength) fenceLength = length;
  }
  final fence = '`' * fenceLength;
  return '$fence$text$fence';
}
