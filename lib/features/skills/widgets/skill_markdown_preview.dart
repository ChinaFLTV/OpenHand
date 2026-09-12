import 'package:flutter/material.dart';

import '../../../shared/ui/markdown_ast_sanitizer.dart';
import '../../../shared/ui/openhand_message_markdown_theme.dart';
import '../../../shared/ui/openhand_safe_markdown_body.dart';
import '../../home/index.dart' show OpenHandHighlightedCodeBlockBuilder;

/// 技能 SKILL.md 预览：去掉 YAML front matter，并与技能详情弹窗共用解析和渲染。
class OpenHandSkillMarkdownPreview extends StatelessWidget {
  const OpenHandSkillMarkdownPreview({
    super.key,
    required this.data,
    this.backgroundColor,
  });

  final String data;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final markdownBackground =
        backgroundColor ?? colorScheme.surfaceContainerLow;
    final markdownTheme = OpenHandMessageMarkdownThemeData.resolve(
      theme: theme,
      backgroundColor: markdownBackground,
      textColor: colorScheme.onSurface,
    );
    return OpenHandSafeMarkdownBody(
      data: stripOpenHandMarkdownFrontMatter(data),
      selectable: true,
      styleSheet: markdownTheme.styleSheet,
      builders: {
        'code': markdownTheme.inlineCodeBuilder,
        'pre': OpenHandHighlightedCodeBlockBuilder(
          theme: theme,
          baseColor: colorScheme.onSurface,
        ),
      },
    );
  }
}
