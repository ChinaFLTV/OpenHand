import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/mcp/data/mcp_market_client.dart';
import 'package:openhand/features/mcp/widgets/mcp_market_dialog.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  for (final size in [
    const Size(1280, 960),
    const Size(600, 700),
    const Size(400, 650),
  ]) {
    testWidgets('市场在 ${size.width} 宽度下展示并打开配置', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? configuredName;
      final client = McpMarketClient(
        httpClient: MockClient((request) async {
          final server = {
            'slug': 'graphlit',
            'name': '图灵知识桥',
            'publisher': 'Graphlit',
            'category': '搜索与信息检索',
            'summary': '连接知识与工具，探索全新的工作方式。',
            'status': 'visible',
          };
          final path = request.url.path;
          if (path.endsWith('/readme')) {
            return _response('# 快速开始\n\n填写连接地址与认证信息。', 200);
          }
          final body = path.endsWith('/categories')
              ? {
                  'items': [
                    {'key': '搜索与信息检索', 'count': 1},
                  ],
                }
              : path.endsWith('/servers')
              ? {
                  'items': [server],
                  'total': 1,
                }
              : server;
          return _response(jsonEncode(body), 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showMcpMarketDialog(
                  context,
                  client: client,
                  onConfigure: (name) async {
                    configuredName = name;
                  },
                ),
                child: const Text('打开市场'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开市场'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('MCP 市场'), findsOneWidget);
      expect(find.text('图灵知识桥'), findsWidgets);
      if (size.width < 800) {
        await tester.tap(find.text('服务详情'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('使用说明'), findsOneWidget);
      }
      await tester.tap(find.text('添加配置'));
      await tester.pumpAndSettle();
      expect(configuredName, '图灵知识桥');
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('MCP 市场'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

http.Response _response(String body, int status) =>
    http.Response.bytes(utf8.encode(body), status);
