import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../features/home/index.dart'
    show OpenHandHighlightedCodeBlockBuilder;
import '../util/text_clip.dart';
import 'markdown_ast_sanitizer.dart';
import 'openhand_safe_markdown_body.dart';

const int kOpenHandMarketMarkdownMaxCharacters = 80000;

/// 文档说明共用预处理、主题样式、高亮代码块和图片预览。
class OpenHandDocumentMarkdownPreview extends StatelessWidget {
  const OpenHandDocumentMarkdownPreview({
    super.key,
    required this.data,
    this.backgroundColor,
    this.maxCharacters,
    this.truncationMessage = '',
    this.emptyMessage = '',
    this.onTapLink,
    this.imageBuilder,
  });

  final String data;
  final Color? backgroundColor;
  final int? maxCharacters;
  final String truncationMessage;
  final String emptyMessage;
  final void Function(String text, String? href, String title)? onTapLink;
  final MarkdownImageBuilder? imageBuilder;

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
      onTapLink: onTapLink,
      imageBuilder: imageBuilder,
      builders: {
        'pre': OpenHandHighlightedCodeBlockBuilder(
          theme: theme,
          baseColor: colorScheme.onSurface,
        ),
      },
    );
  }
}
