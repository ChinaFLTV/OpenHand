import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

const EdgeInsets openHandMarkdownInlineCodePadding = EdgeInsets.symmetric(
  horizontal: 6,
  vertical: 1.5,
);
const BorderRadius openHandMarkdownInlineCodeRadius = BorderRadius.all(
  Radius.circular(5),
);

class OpenHandMarkdownInlineCodeBuilder extends MarkdownElementBuilder {
  OpenHandMarkdownInlineCodeBuilder({
    required this.textStyle,
    required this.backgroundColor,
  });

  final TextStyle textStyle;
  final Color backgroundColor;

  Widget buildChip(String text) {
    return OpenHandMarkdownInlineCode(
      text: text,
      textStyle: textStyle,
      backgroundColor: backgroundColor,
    );
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent;
    // 块级代码由 pre 构建器处理；Markdown 解析器会为其保留结尾换行。
    if (text.isEmpty || text.endsWith('\n')) return null;
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        style: textStyle,
        child: buildChip(text),
      ),
    );
  }
}

class OpenHandMarkdownInlineCode extends StatelessWidget {
  const OpenHandMarkdownInlineCode({
    super.key,
    required this.text,
    required this.textStyle,
    required this.backgroundColor,
  });

  final String text;
  final TextStyle textStyle;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: openHandMarkdownInlineCodeRadius,
        ),
        child: Padding(
          padding: openHandMarkdownInlineCodePadding,
          child: Text(
            text,
            // WidgetSpan 已按系统文字缩放比例整体缩放胶囊，子文本不再重复缩放。
            textScaler: TextScaler.noScaling,
            style: textStyle.copyWith(backgroundColor: Colors.transparent),
          ),
        ),
      ),
    );
  }
}
