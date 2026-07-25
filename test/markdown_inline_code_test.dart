import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:openhand/shared/ui/markdown_inline_code.dart';

void main() {
  const codeColor = Color(0xFFF2F3F5);
  const codeStyle = TextStyle(
    color: Color(0xFF25282D),
    fontFamily: 'monospace',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.28,
  );

  OpenHandMarkdownInlineCodeBuilder buildInlineCodeBuilder() {
    return OpenHandMarkdownInlineCodeBuilder(
      textStyle: codeStyle,
      backgroundColor: codeColor,
    );
  }

  testWidgets('行内代码使用语雀风格圆角组件并保持基线对齐', (tester) async {
    final builder = buildInlineCodeBuilder();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 620,
            child: MarkdownBody(
              data: '业务机器部署 `Docker`，仅使用 `172.12.0.0/24` 网段。',
              selectable: true,
              builders: <String, MarkdownElementBuilder>{'code': builder},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final chips = tester.widgetList<OpenHandMarkdownInlineCode>(
      find.byType(OpenHandMarkdownInlineCode),
    );
    expect(chips.map((chip) => chip.text), <String>['Docker', '172.12.0.0/24']);
    for (final chip in chips) {
      expect(chip.backgroundColor, codeColor);
      expect(chip.textStyle, codeStyle);
    }

    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(OpenHandMarkdownInlineCode).first,
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding, openHandMarkdownInlineCodePadding);
    final decoration = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(OpenHandMarkdownInlineCode).first,
        matching: find.byType(DecoratedBox),
      ),
    );
    expect(
      (decoration.decoration as BoxDecoration).borderRadius,
      openHandMarkdownInlineCodeRadius,
    );

    final spans = <WidgetSpan>[];
    for (final selectable in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    )) {
      _collectWidgetSpans(selectable.textSpan, spans);
    }
    expect(spans, hasLength(2));
    for (final span in spans) {
      expect(span.alignment, PlaceholderAlignment.baseline);
      expect(span.baseline, TextBaseline.alphabetic);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('超长行内代码在窄布局中不会横向溢出', (tester) async {
    final builder = buildInlineCodeBuilder();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: MarkdownBody(
              data:
                  '路径 `very-long-directory/another-directory/file-name-with-hash-1234567890.dart`。',
              builders: <String, MarkdownElementBuilder>{'code': builder},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(OpenHandMarkdownInlineCode), findsOneWidget);
    expect(
      tester.getSize(find.byType(OpenHandMarkdownInlineCode)).width,
      lessThanOrEqualTo(180),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('围栏代码块不会套用行内代码胶囊', (tester) async {
    final builder = buildInlineCodeBuilder();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: '```dart\nvoid main() {}\n```',
            builders: <String, MarkdownElementBuilder>{
              'code': builder,
              'pre': _TestCodeBlockBuilder(),
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('代码块'), findsOneWidget);
    expect(find.byType(OpenHandMarkdownInlineCode), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _collectWidgetSpans(InlineSpan? span, List<WidgetSpan> result) {
  if (span == null) return;
  if (span is WidgetSpan) result.add(span);
  span.visitDirectChildren((child) {
    _collectWidgetSpans(child, result);
    return true;
  });
}

class _TestCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return const Text('代码块');
  }
}
