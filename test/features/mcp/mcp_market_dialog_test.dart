import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/features/mcp/data/mcp_market_client.dart';
import 'package:openhand/features/mcp/widgets/mcp_market_dialog.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/oh_pill.dart';
import 'package:openhand/shared/ui/openhand_safe_scrollbar.dart';

void main() {
  for (final (size, textScale) in [
    (const Size(1280, 960), 1.0),
    (const Size(600, 700), 1.0),
    (const Size(400, 650), 1.0),
    (const Size(1280, 960), 1.8),
  ]) {
    testWidgets('市场在 ${size.width} 宽度、$textScale 倍字体下展示并打开配置', (tester) async {
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
          theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
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
      for (final label in ['全部', '搜索与信息检索 · 1']) {
        final text = find.text(label);
        final chip = find.ancestor(
          of: text,
          matching: find.byType(OpenHandChoicePill),
        );
        expect(
          (tester.getCenter(text).dy - tester.getCenter(chip).dy).abs(),
          lessThan(1),
          reason: '分类胶囊的选中态与未选中态文字均应垂直居中',
        );
      }
      await tester.tap(find.text('搜索与信息检索 · 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      for (final bar in tester.widgetList<OpenHandSafeScrollbar>(
        find.byType(OpenHandSafeScrollbar, skipOffstage: false),
      )) {
        expect(
          bar.controller?.positions.length ?? 0,
          lessThanOrEqualTo(1),
          reason: '分类切换的新旧列表不能共享控制器',
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('图灵知识桥'), findsWidgets);
      if (size.width < 800) {
        await tester.tap(find.text('服务详情'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('使用说明'), findsOneWidget);
        for (final tab in ['浏览服务', '服务详情', '浏览服务', '服务详情']) {
          await tester.tap(find.text(tab));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 40));
          for (final bar in tester.widgetList<OpenHandSafeScrollbar>(
            find.byType(OpenHandSafeScrollbar, skipOffstage: false),
          )) {
            expect(
              bar.controller?.positions.length ?? 0,
              lessThanOrEqualTo(1),
              reason: '切换动画的新旧面板必须独立持有滚动位置',
            );
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
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
  testWidgets('长说明切换到短说明及快速往返时不溢出，仍可滚动到底部', (tester) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final servers = [
      {'slug': 'long', 'name': '长说明服务', 'status': 'visible'},
      {'slug': 'short', 'name': '短说明服务', 'status': 'visible'},
    ];
    final client = McpMarketClient(
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/readme')) {
          return _response(
            path.contains('/long/')
                ? '${List.generate(80, (index) => '第 $index 段使用说明。').join('\n\n')}\n\n文档末尾'
                : '简短说明',
            200,
          );
        }
        final body = path.endsWith('/categories')
            ? {'items': []}
            : path.endsWith('/servers')
            ? {'items': servers, 'total': servers.length}
            : servers.firstWhere(
                (server) => path.endsWith('/${server['slug']}'),
              );
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
                onConfigure: (_) async {},
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
    final detailScroll = find
        .ancestor(
          of: find.byKey(const ValueKey('long')),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    final scroll = tester
        .widget<SingleChildScrollView>(detailScroll)
        .controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(1000));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(find.text('文档末尾').hitTestable(), findsOneWidget);
    for (final name in ['短说明服务', '长说明服务', '短说明服务']) {
      await tester.tap(find.text(name).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('long')), findsNothing);
    expect(scroll.offset, 0);
    expect(scroll.position.maxScrollExtent, lessThan(1000));
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('英文界面展示市场弹窗的当前语言文案，而不是写死中文', (tester) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = McpMarketClient(
      httpClient: MockClient((request) async {
        final server = {
          'slug': 'graphlit',
          'name': '图灵知识桥',
          'publisher': 'Graphlit',
          'category': '搜索与信息检索',
          'summary': '连接知识与工具。',
          'status': 'visible',
        };
        final path = request.url.path;
        if (path.endsWith('/readme')) {
          return _response('# Getting started', 200);
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
        theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMcpMarketDialog(
                context,
                client: client,
                onConfigure: (_) async {},
              ),
              child: const Text('Open market'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open market'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('MCP Market'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Search & retrieval · 1'), findsOneWidget);
    expect(find.text('MCP service'), findsWidgets);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Add configuration'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('MCP 市场'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('项目来源展示可点击卡片，并用系统浏览器打开合法链接', (tester) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = <String>[];
    final client = McpMarketClient(
      httpClient: MockClient((request) async {
        final server = {
          'slug': 'tapd',
          'name': '腾讯云TAPD MCP Server',
          'publisher': '腾讯云TAPD团队',
          'category': '腾讯产品MCP',
          'summary': '与 TAPD API 无缝集成。',
          'status': 'visible',
          'repoUrl': 'javascript:alert(1)',
          'homepage': 'https://example.com/home',
          'sourceUrl': 'https://skillhub.example/mcp/tapd',
        };
        final path = request.url.path;
        if (path.endsWith('/readme')) {
          return _response('# TAPD MCP Server\n\n查看说明。', 200);
        }
        final body = path.endsWith('/categories')
            ? {'items': []}
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
        theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMcpMarketDialog(
                context,
                client: client,
                onConfigure: (_) async {},
                openHttpUrl: (url) async {
                  opened.add(url);
                  return true;
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
    expect(find.text('项目来源'), findsOneWidget);
    expect(find.text('代码仓库'), findsNothing);
    expect(find.text('项目主页'), findsOneWidget);
    expect(find.text('服务来源'), findsOneWidget);
    expect(find.text('example.com/home'), findsOneWidget);
    expect(find.text('skillhub.example/mcp/tapd'), findsOneWidget);
    await tester.tap(find.text('项目主页'));
    await tester.pumpAndSettle();
    expect(opened, ['https://example.com/home']);
    await tester.tap(find.text('服务来源'));
    await tester.pumpAndSettle();
    expect(opened, [
      'https://example.com/home',
      'https://skillhub.example/mcp/tapd',
    ]);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });
}

http.Response _response(String body, int status) =>
    http.Response.bytes(utf8.encode(body), status);
