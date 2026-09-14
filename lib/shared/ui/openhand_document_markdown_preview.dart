import 'package:flutter/material.dart';

import '../../features/home/index.dart'
    show OpenHandHighlightedCodeBlockBuilder;
import '../util/text_clip.dart';
import 'markdown_ast_sanitizer.dart';
import 'openhand_safe_markdown_body.dart';

const int kOpenHandMarketMarkdownMaxCharacters = 80000;

/// 技能与 MCP 说明共用预处理、主题样式和高亮代码块。
class OpenHandDocumentMarkdownPreview extends StatelessWidget {
  const OpenHandDocumentMarkdownPreview({
    super.key,
    required this.data,
    this.backgroundColor,
    this.maxCharacters,
    this.truncationMessage = '',
    this.emptyMessage = '',
  });

  final String data;
  final Color? backgroundColor;
  final int? maxCharacters;
  final String truncationMessage;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final markdownBackground =
        backgroundColor ?? colorScheme.surfaceContainerLow;
    var markdown = stripOpenHandMarkdownFrontMatter(data).trim();
    if (markdown.isEmpty) {
      return Text(
        emptyMessage,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }
    final limit = maxCharacters;
    if (limit != null && markdown.length > limit) {
      markdown = clipTextByCodeUnits(
        markdown,
        limit,
        suffix: truncationMessage,
      );
    }
    return OpenHandThemedMarkdownBody(
      data: markdown,
      backgroundColor: markdownBackground,
      textColor: colorScheme.onSurface,
      builders: {
        'pre': OpenHandHighlightedCodeBlockBuilder(
          theme: theme,
          baseColor: colorScheme.onSurface,
        ),
      },
    );
  }
}
