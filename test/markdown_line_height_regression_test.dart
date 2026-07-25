import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Markdown 富文本不会用强制 Strut 压缩混合字形', (tester) async {
    const source =
        '普通文本**大号粗体**  \n'
        '普通文本**大号粗体**  \n'
        '普通文本**大号粗体**  \n'
        '普通文本**大号粗体**';
    final styleSheet = MarkdownStyleSheet(
      p: const TextStyle(fontSize: 14, height: 1.2),
      strong: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: MarkdownBody(data: source, styleSheet: styleSheet),
          ),
        ),
      ),
    );
    await tester.pump();

    final paragraphFinder = find.byWidgetPredicate((widget) {
      return widget is Text &&
          (widget.textSpan?.toPlainText() ?? '').contains('普通文本大号粗体');
    });
    expect(paragraphFinder, findsOneWidget);

    final paragraph = tester.widget<Text>(paragraphFinder);
    expect(paragraph.strutStyle?.forceStrutHeight, isFalse);
    expect(tester.getSize(paragraphFinder).height, greaterThan(100));
  });

  testWidgets('截图中的中文段落保持安全行高', (tester) async {
    const source = '''
本次无法把“访问异常”的具体根因定到状态码、边缘节点或回源错误：原始 CDN 日志包查询被云管平台白名单拦截，封禁检查接口也返回内部错误。因此没有证据支持将异常归因到阿里云/百度云，或直接断言腾讯云回源失败、鉴权拒绝等。

建议补取腾讯云该域名 `2026-07-23 15:00:00–16:00:00` 的 CDN 访问日志包，按以下条件过滤：
''';
    final styleSheet = MarkdownStyleSheet(
      p: const TextStyle(fontSize: 14.56, height: 1.5),
      code: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12.6,
        height: 1.35,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 680,
            child: MarkdownBody(
              data: source,
              selectable: true,
              styleSheet: styleSheet,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final paragraphs = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .where(
          (widget) => (widget.textSpan?.toPlainText() ?? '').trim().isNotEmpty,
        );
    expect(paragraphs, hasLength(2));
    for (final paragraph in paragraphs) {
      expect(paragraph.strutStyle?.forceStrutHeight, isFalse);
    }
    expect(tester.takeException(), isNull);
  });
}
