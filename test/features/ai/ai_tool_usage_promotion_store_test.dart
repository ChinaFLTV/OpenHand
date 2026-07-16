import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  late Directory tempDirectory;
  late String filePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_tool_usage_',
    );
    filePath = '${tempDirectory.path}/tool_usage_promotion.json';
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('严格超过会话调用占比 50% 后才晋升', () async {
    final store = AiToolUsagePromotionStore(filePath: filePath);
    await store.initialize();

    final query = await store.recordToolCall(
      sessionId: 'session-1',
      catalog: _catalog,
      toolCall: _toolSearchCall,
      resultMetadata: const <String, Object?>{
        'tool_search_loaded_names': <String>[_deferredToolName],
      },
    );
    final firstGatewayCall = await store.recordToolCall(
      sessionId: 'session-1',
      catalog: _catalog,
      toolCall: _toolSearchCall,
      resultMetadata: const <String, Object?>{
        'tool_search_gateway': true,
        'tool_search_gateway_tool_name': _deferredToolName,
      },
    );

    expect(query.toolId, 'ToolSearch');
    expect(firstGatewayCall.sessionCallCount, 1);
    expect(firstGatewayCall.sessionTotalCallCount, 2);
    expect(firstGatewayCall.promotedNow, isFalse);
    expect(store.promotedToolIdsForSession('session-1'), isEmpty);

    final secondGatewayCall = await store.recordToolCall(
      sessionId: 'session-1',
      catalog: _catalog,
      toolCall: _toolSearchCall,
      resultMetadata: const <String, Object?>{
        'tool_search_gateway': true,
        'tool_search_gateway_tool_name': _deferredToolName,
      },
    );

    expect(secondGatewayCall.sessionCallCount, 2);
    expect(secondGatewayCall.sessionTotalCallCount, 3);
    expect(secondGatewayCall.promotedNow, isTrue);
    expect(store.promotedToolIdsForSession('session-1'), <String>{
      _deferredToolName,
    });
    expect(store.dayCounts, <String, int>{
      'ToolSearch': 1,
      _deferredToolName: 2,
    });
    expect(store.monthCounts, store.dayCounts);
    expect(store.yearCounts, store.dayCounts);
    await store.flush();
  });

  test('ToolSearch 查询不会统计或晋升匹配到的目标工具', () async {
    final store = AiToolUsagePromotionStore(filePath: filePath);
    await store.initialize();

    await store.recordToolCall(
      sessionId: 'session-1',
      catalog: _catalog,
      toolCall: _toolSearchCall,
      resultMetadata: const <String, Object?>{
        'tool_search_loaded_names': <String>[_deferredToolName],
      },
    );

    final snapshot = store.sessionSnapshot('session-1')!;
    expect(snapshot.totalCallCount, 1);
    expect(snapshot.toolCallCounts, <String, int>{'ToolSearch': 1});
    expect(snapshot.promotedToolIds, isEmpty);
    await store.flush();
  });

  test('晋升状态在重启后保持', () async {
    final firstStore = AiToolUsagePromotionStore(filePath: filePath);
    await firstStore.initialize();
    await firstStore.record(
      sessionId: 'session-1',
      toolId: _deferredToolName,
      promotionEligible: true,
    );
    await firstStore.flush();

    final restoredStore = AiToolUsagePromotionStore(filePath: filePath);
    await restoredStore.initialize();

    expect(restoredStore.promotedToolIdsForSession('session-1'), <String>{
      _deferredToolName,
    });
    expect(restoredStore.sessionSnapshot('session-1')!.totalCallCount, 1);
    expect(restoredStore.dayCounts[_deferredToolName], 1);
  });

  test('已晋升工具在占比回落后保持稳定', () async {
    final store = AiToolUsagePromotionStore(filePath: filePath);
    await store.initialize();
    await store.record(
      sessionId: 'session-1',
      toolId: _deferredToolName,
      promotionEligible: true,
    );
    await store.record(sessionId: 'session-1', toolId: 'Read');
    await store.record(sessionId: 'session-1', toolId: 'Write');

    expect(store.sessionSnapshot('session-1')!.totalCallCount, 3);
    expect(store.promotedToolIdsForSession('session-1'), <String>{
      _deferredToolName,
    });
    await store.flush();
  });

  test('日月年统计会按周期独立滚动', () async {
    var now = DateTime(2026, 1, 31, 12);
    final store = AiToolUsagePromotionStore(
      filePath: filePath,
      clock: () => now,
    );
    await store.initialize();
    await store.record(sessionId: 'session-1', toolId: 'Read');

    now = DateTime(2026, 2, 1, 12);
    await store.record(sessionId: 'session-1', toolId: 'Read');
    expect(store.dayCounts, <String, int>{'Read': 1});
    expect(store.monthCounts, <String, int>{'Read': 1});
    expect(store.yearCounts, <String, int>{'Read': 2});

    now = DateTime(2027, 1, 1, 12);
    await store.record(sessionId: 'session-1', toolId: 'Read');
    expect(store.dayCounts, <String, int>{'Read': 1});
    expect(store.monthCounts, <String, int>{'Read': 1});
    expect(store.yearCounts, <String, int>{'Read': 1});
    await store.flush();
  });

  test('并发记录不会丢失调用次数', () async {
    final store = AiToolUsagePromotionStore(filePath: filePath);
    await store.initialize();

    await Future.wait(<Future<AiToolUsageRecord>>[
      for (var index = 0; index < 100; index++)
        store.record(sessionId: 'session-1', toolId: 'Read'),
    ]);

    final snapshot = store.sessionSnapshot('session-1')!;
    expect(snapshot.totalCallCount, 100);
    expect(snapshot.toolCallCounts['Read'], 100);
    expect(store.dayCounts['Read'], 100);
    await store.flush();
  });

  test('损坏或超大文件会安全回落为空状态', () async {
    final file = File(filePath);
    await file.writeAsString('{invalid');
    final corruptedStore = AiToolUsagePromotionStore(filePath: filePath);
    await corruptedStore.initialize();
    expect(corruptedStore.sessionSnapshot('session-1'), isNull);
    await corruptedStore.record(sessionId: 'session-1', toolId: 'Read');
    await corruptedStore.flush();

    await file.writeAsBytes(List<int>.filled(4 * 1024 * 1024 + 1, 0x20));
    final oversizedStore = AiToolUsagePromotionStore(filePath: filePath);
    await oversizedStore.initialize();
    expect(oversizedStore.sessionSnapshot('session-1'), isNull);
    await oversizedStore.record(sessionId: 'session-2', toolId: 'Write');
    await oversizedStore.flush();

    expect(await file.length(), lessThan(4 * 1024 * 1024));
    expect(oversizedStore.sessionSnapshot('session-2')!.totalCallCount, 1);
  });
}

const String _deferredToolName = 'mcp__server__remote_action';

const AiResolvedTool _toolSearch = AiResolvedTool(
  name: 'ToolSearch',
  definition: AiToolDefinition(
    name: 'ToolSearch',
    description: '固定工具网关。',
    parameters: <String, Object?>{'type': 'object'},
  ),
  source: AiRuntimeToolSource.builtin,
  builtinKind: AiBuiltinToolKind.toolSearch,
);

final AiResolvedToolCatalog _catalog = AiResolvedToolCatalog(
  definitions: <AiToolDefinition>[_toolSearch.definition],
  toolsByName: <String, AiResolvedTool>{'ToolSearch': _toolSearch},
);

const AiToolCall _toolSearchCall = AiToolCall(
  id: 'call-1',
  name: 'ToolSearch',
  arguments: '{}',
);
