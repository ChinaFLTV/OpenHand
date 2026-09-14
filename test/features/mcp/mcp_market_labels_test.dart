import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/model/mcp_market.dart';
import 'package:openhand/features/mcp/widgets/mcp_market_labels.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  Future<String> pumpLabel(
    WidgetTester tester,
    Locale locale,
    String Function(BuildContext context) read,
  ) async {
    late String value;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            value = read(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return value;
  }

  testWidgets('分类与类型标签跟随当前语言，未知中文键不再被改成英文标题', (tester) async {
    expect(
      await pumpLabel(
        tester,
        const Locale('zh'),
        (context) => mcpMarketCategoryLabel(context, '搜索与信息检索'),
      ),
      '搜索与信息检索',
    );
    expect(
      await pumpLabel(
        tester,
        const Locale('en'),
        (context) => mcpMarketCategoryLabel(context, '搜索与信息检索'),
      ),
      'Search & retrieval',
    );
    expect(
      await pumpLabel(
        tester,
        const Locale('ja'),
        (context) => mcpMarketCategoryLabel(context, '数据库与文件'),
      ),
      'データベースとファイル',
    );
    expect(
      await pumpLabel(
        tester,
        const Locale('zh'),
        (context) => mcpMarketCategoryLabel(context, '自定义分类'),
      ),
      '自定义分类',
    );
    expect(
      await pumpLabel(
        tester,
        const Locale('fr'),
        mcpMarketTypeLabel,
      ),
      'Service MCP',
    );
  });

  testWidgets('概述优先使用接口原文，不把中文介绍硬译成英文', (tester) async {
    final server = McpMarketServer.fromJson({
      'slug': 'demo',
      'name': '图灵知识桥',
      'summary': '连接知识与工具。',
      'summaryZh': '',
      'status': 'visible',
    });
    expect(
      await pumpLabel(
        tester,
        const Locale('en'),
        (context) => mcpMarketSummary(context, server),
      ),
      '连接知识与工具。',
    );
    expect(
      await pumpLabel(
        tester,
        const Locale('zh'),
        (context) => mcpMarketSummary(context, server),
      ),
      '连接知识与工具。',
    );
  });
}
