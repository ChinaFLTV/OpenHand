import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/index.dart'
    show OpenHandHighlightedCodeBlockBuilder;
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/openhand_document_markdown_preview.dart';
import 'package:openhand/shared/ui/openhand_safe_markdown_body.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('说明在 $brightness 下正确处理元信息、表格和代码块', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: OpenHandDocumentMarkdownPreview(
                  backgroundColor: Colors.transparent,
                  data:
                      '\ufeff---\r\nname: 隐藏元信息\r\n---\r\n\r\n# 使用说明\r\n\r\n'
                      '| 工具 | 说明 |\n| --- | --- |\n| 检索 | 查询内容 |\n\n'
                      '```json\n{"command": "npx", "args": ["示例"]}\n```\n\n'
                      '> 提示\n\n- 列表条目\n\n[项目文档](https://example.com)',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('使用说明'), findsOneWidget);
      expect(find.text('隐藏元信息'), findsNothing);
      expect(find.byType(Table), findsWidgets);
      final markdown = tester.widget<OpenHandThemedMarkdownBody>(
        find.byType(OpenHandThemedMarkdownBody),
      );
      expect(
        markdown.builders['pre'],
        isA<OpenHandHighlightedCodeBlockBuilder>(),
      );
      expect(markdown.backgroundColor, Colors.transparent);
      expect(markdown.data, isNot(contains('隐藏元信息')));
    });
  }

  testWidgets('先去除元信息再截断，并避免切断 Unicode 字符', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpenHandDocumentMarkdownPreview(
            data: '---\nname: 元信息\n---\n123😀后续正文',
            maxCharacters: 8,
            truncationMessage: '截断提示',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final markdown = tester.widget<OpenHandThemedMarkdownBody>(
      find.byType(OpenHandThemedMarkdownBody),
    );
    expect(markdown.data, '123截断提示');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpenHandDocumentMarkdownPreview(
            data: '---\nname: 元信息\n---\n',
            emptyMessage: '暂无说明',
          ),
        ),
      ),
    );
    expect(find.text('暂无说明'), findsOneWidget);
    expect(find.byType(OpenHandThemedMarkdownBody), findsNothing);
  });
}
