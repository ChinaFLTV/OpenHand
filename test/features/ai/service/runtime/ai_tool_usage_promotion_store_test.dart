import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_usage_promotion_store.dart';
import 'package:openhand/features/mcp/index.dart';

void main() {
  late Directory temporaryDirectory;
  late String storePath;
  final now = DateTime.utc(2026, 7, 17, 8, 30);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-resource-usage-',
    );
    storePath = '${temporaryDirectory.path}/usage.json';
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('v2 聚合数据可迁移为 v3', () async {
    await File(storePath).writeAsString(
      jsonEncode(<String, Object?>{
        'version': 2,
        'periods': <String, Object?>{
          'day': <String, Object?>{
            '2026-07-17': <String, Object?>{
              'counts': <String, Object?>{
                'tool': <String, int>{'Read': 2},
              },
              'totals': <String, int>{'tool': 2},
            },
          },
        },
        'sessions': <String, Object?>{},
      }),
    );
    final store = _store(storePath, now);

    await store.initialize();
    expect(
      store
          .snapshot(kind: AiResourceUsageKind.tool)
          .level(AiResourceUsagePeriod.day)
          .totalCount,
      2,
    );
    await store.flush();

    final persisted = jsonDecode(await File(storePath).readAsString()) as Map;
    expect(persisted['version'], 3);
  });

  test('MCP 服务按 Tool 保存成功状态、耗时和脱敏事件', () async {
    const definition = AiToolDefinition(
      name: 'mcp_demo_search',
      description: 'demo',
      parameters: <String, Object?>{'type': 'object'},
    );
    final resolvedTool = AiResolvedTool(
      name: definition.name,
      definition: definition,
      source: AiRuntimeToolSource.mcp,
      mcpServer: const McpServer(
        name: 'demo-server',
        type: McpServerType.streamableHttp,
        enabled: true,
      ),
      mcpTool: const McpTool(
        id: 'search',
        name: 'search',
        description: 'demo',
        inputSchema: <String, Object?>{},
      ),
    );
    final catalog = AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[definition],
      toolsByName: <String, AiResolvedTool>{definition.name: resolvedTool},
    );
    final store = _store(storePath, now);

    await store.recordToolCall(
      sessionId: 'session-1',
      catalog: catalog,
      toolCall: const AiToolCall(
        id: 'call-1',
        name: 'mcp_demo_search',
        arguments: '{"query":"OpenHand","token":"private-token"}',
      ),
      result: const AiToolExecutionResult(
        status: BashToolExecutionStatus.success,
        command: 'search',
        workingDirectory: '/',
        stdout: 'ok',
        stderr: '',
        durationMs: 125,
        resultText: '找到结果',
        metadata: <String, Object?>{
          'tool_source': 'mcp',
          'mcp_server_name': 'demo-server',
          'mcp_tool_id': 'search',
          'mcp_tool_name': 'search',
        },
      ),
    );

    final level = store
        .snapshot(
          kind: AiResourceUsageKind.mcp,
          preferredSessionId: 'session-1',
        )
        .level(AiResourceUsagePeriod.session);
    expect(level.successCount, 1);
    expect(level.averageDurationMs, 125);
    expect(level.sessionCount, 1);
    expect(level.resources.single.resourceId, 'demo-server');
    expect(level.resources.single.subResources.single.resourceId, 'search');
    expect(level.recentEvents.single.argumentsSummary, contains('[已脱敏]'));
    expect(
      level.recentEvents.single.argumentsSummary,
      isNot(contains('private-token')),
    );
  });

  test('失败事件可恢复且最近记录保持有界', () async {
    final store = _store(storePath, now);
    for (var index = 0; index < 400; index++) {
      await store.recordResources(
        sessionId: 'session-$index',
        resources: const <AiResourceUsageKind, Iterable<String>>{
          AiResourceUsageKind.hook: <String>['hook-1'],
        },
        subResourceId: 'post_tool_use',
        status: 'failed',
        durationMs: index,
        errorSummary: '执行失败',
        source: 'user_hook',
      );
    }
    await store.flush();

    final persisted = jsonDecode(await File(storePath).readAsString()) as Map;
    expect((persisted['recent_events'] as List).length, 384);

    final restored = _store(storePath, now);
    await restored.initialize();
    final level = restored
        .snapshot(kind: AiResourceUsageKind.hook)
        .level(AiResourceUsagePeriod.day);
    expect(level.failureCount, 400);
    expect(level.recentEvents.length, 80);
    expect(level.recentEvents.first.errorSummary, '执行失败');
  });
}

AiToolUsagePromotionStore _store(String path, DateTime now) {
  return AiToolUsagePromotionStore(
    filePath: path,
    clock: () => now,
    persistDebounce: const Duration(days: 1),
  );
}
