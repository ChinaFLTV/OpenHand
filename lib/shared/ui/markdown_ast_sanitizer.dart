import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import '../util/input_value_parsing.dart';
import 'markdown_math.dart';

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
