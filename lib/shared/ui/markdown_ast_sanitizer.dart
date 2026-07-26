import 'package:markdown/markdown.dart' as md;

import '../util/input_value_parsing.dart';

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
