import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GitHub 风格 Markdown 可完整渲染', (tester) async {
    const source = '''
# 标题

> **引用内容**与`行内代码`

- [x] 已完成
- [ ] 待处理

| 名称 | 状态 |
| --- | --- |
| OpenHand | 正常 |

```dart
void main() => print('ok');
```
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownBody(data: source, selectable: true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    final renderedText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
        .join('\n');
    expect(renderedText, contains('引用内容'));
    expect(renderedText, contains("void main() => print('ok');"));
  });

  testWidgets('未闭合代码围栏不会导致渲染异常', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownBody(data: '```dart\nvoid main() {', selectable: true),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SelectableText), findsWidgets);
  });
}
