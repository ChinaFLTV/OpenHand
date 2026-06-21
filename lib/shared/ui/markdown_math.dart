import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import 'animated_dialog.dart';

const String openHandMarkdownMathInlineTag = 'openhand-math-inline';
const String openHandMarkdownMathBlockTag = 'openhand-math-block';
const int openHandMarkdownMathSyntaxVersion = 1;

final List<md.BlockSyntax> openHandMarkdownMathBlockSyntaxes = <md.BlockSyntax>[
  _OpenHandMathBlockSyntax(),
];

final List<md.InlineSyntax> openHandMarkdownMathInlineSyntaxes =
    <md.InlineSyntax>[_OpenHandInlineMathSyntax()];

List<md.InlineSyntax> withOpenHandMarkdownMathInlineSyntaxes(
  List<md.InlineSyntax> syntaxes,
) {
  if (syntaxes.isEmpty) {
    return openHandMarkdownMathInlineSyntaxes;
  }
  return <md.InlineSyntax>[...openHandMarkdownMathInlineSyntaxes, ...syntaxes];
}

Map<String, MarkdownElementBuilder> withOpenHandMarkdownMathBuilders(
  Map<String, MarkdownElementBuilder> builders, {
  required TextStyle? fallbackTextStyle,
  required Color? textColor,
}) {
  final merged = <String, MarkdownElementBuilder>{...builders};
  merged.putIfAbsent(
    openHandMarkdownMathInlineTag,
    () => OpenHandMarkdownMathBuilder.inline(
      fallbackTextStyle: fallbackTextStyle,
      textColor: textColor,
    ),
  );
  merged.putIfAbsent(
    openHandMarkdownMathBlockTag,
    () => OpenHandMarkdownMathBuilder.display(
      fallbackTextStyle: fallbackTextStyle,
      textColor: textColor,
    ),
  );
  return merged;
}

class _OpenHandInlineMathSyntax extends md.InlineSyntax {
  _OpenHandInlineMathSyntax()
    : super(r'\\\(([\s\S]+?)\\\)', startCharacter: 0x5C);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tex = (match[1] ?? '').trim();
    if (tex.isEmpty) {
      parser.addNode(md.Text(match[0] ?? ''));
      return true;
    }
    parser.addNode(md.Element.text(openHandMarkdownMathInlineTag, tex));
    return true;
  }
}

class _OpenHandMathBlockSyntax extends md.BlockSyntax {
  static final RegExp _pattern = RegExp(r'^[ ]{0,3}(?:\\\[|\$\$)');
  static const int _maxBlockLines = 80;

  @override
  RegExp get pattern => _pattern;

  @override
  md.Node parse(md.BlockParser parser) {
    final rawLines = <String>[];
    final firstLine = parser.current.content;
    final firstTrimmed = firstLine.trimLeft();
    final opening = firstTrimmed.startsWith(r'\[') ? r'\[' : r'$$';
    final closing = opening == r'\[' ? r'\]' : r'$$';
    final texLines = <String>[];
    var closed = false;

    String afterOpening(String line) {
      final index = line.indexOf(opening);
      if (index < 0) return line;
      return line.substring(index + opening.length);
    }

    void consumeBodySegment(String segment) {
      final closingIndex = segment.indexOf(closing);
      if (closingIndex >= 0) {
        texLines.add(segment.substring(0, closingIndex));
        closed = true;
        return;
      }
      texLines.add(segment);
    }

    rawLines.add(firstLine);
    parser.advance();
    consumeBodySegment(afterOpening(firstLine));

    while (!closed && !parser.isDone && rawLines.length < _maxBlockLines) {
      final line = parser.current.content;
      if (line.trim().isEmpty) {
        break;
      }
      rawLines.add(line);
      parser.advance();
      consumeBodySegment(line);
    }

    final tex = texLines.join('\n').trim();
    if (!closed || tex.isEmpty) {
      return md.Element('p', <md.Node>[md.Text(rawLines.join('\n'))]);
    }
    return md.Element(openHandMarkdownMathBlockTag, <md.Node>[md.Text(tex)]);
  }
}

class OpenHandMarkdownMathBuilder extends MarkdownElementBuilder {
  OpenHandMarkdownMathBuilder.display({
    required this.fallbackTextStyle,
    required this.textColor,
  }) : display = true;

  OpenHandMarkdownMathBuilder.inline({
    required this.fallbackTextStyle,
    required this.textColor,
  }) : display = false;

  final bool display;
  final TextStyle? fallbackTextStyle;
  final Color? textColor;

  @override
  bool isBlockElement() => display;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.textContent.trim();
    if (tex.isEmpty) return null;
    final defaultStyle = DefaultTextStyle.of(context).style;
    final baseStyle = parentStyle ?? preferredStyle ?? fallbackTextStyle;
    final effectiveStyle = defaultStyle
        .merge(baseStyle)
        .copyWith(color: textColor ?? baseStyle?.color ?? defaultStyle.color);

    final math = _OpenHandMarkdownMath(
      tex: tex,
      display: display,
      textStyle: effectiveStyle,
    );
    if (!display) {
      return math;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 0.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: openHandDialogAwareScrollPhysics(context),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: Align(child: math),
            ),
          );
        },
      ),
    );
  }
}

class _OpenHandMarkdownMath extends StatefulWidget {
  const _OpenHandMarkdownMath({
    required this.tex,
    required this.display,
    required this.textStyle,
  });

  final String tex;
  final bool display;
  final TextStyle textStyle;

  @override
  State<_OpenHandMarkdownMath> createState() => _OpenHandMarkdownMathState();
}

class _OpenHandMarkdownMathState extends State<_OpenHandMarkdownMath> {
  static const TexParserSettings _parserSettings = TexParserSettings(
    strict: Strict.ignore,
    maxExpand: 500,
  );

  late Widget _math = _buildMath();

  @override
  void didUpdateWidget(covariant _OpenHandMarkdownMath oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tex != widget.tex ||
        oldWidget.display != widget.display ||
        oldWidget.textStyle != widget.textStyle) {
      _math = _buildMath();
    }
  }

  Widget _buildMath() {
    final raw = widget.display
        ? '\\[\n${widget.tex}\n\\]'
        : '\\(${widget.tex}\\)';
    return Math.tex(
      widget.tex,
      mathStyle: widget.display ? MathStyle.display : MathStyle.text,
      textStyle: widget.textStyle,
      settings: _parserSettings,
      onErrorFallback: (_) => Text(raw, style: widget.textStyle),
    );
  }

  @override
  Widget build(BuildContext context) => _math;
}
