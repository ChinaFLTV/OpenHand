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
    await store.flush();
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

  test('嵌套执行统一归入根会话', () async {
    final store = _store(storePath, now);
    for (final sessionId in const <String>[
      'session-root',
      'session-root::parallel-bash::call-1',
      'session-root/agent/agent-1/task/task-1',
      'session-root/task/call-2',
    ]) {
      await store.recordResources(
        sessionId: sessionId,
        resources: const <AiResourceUsageKind, Iterable<String>>{
          AiResourceUsageKind.hook: <String>['hook-1'],
        },
      );
    }

    final level = store
        .snapshot(
          kind: AiResourceUsageKind.hook,
          preferredSessionId: 'session-root/agent/agent-1/task/task-1',
        )
        .level(AiResourceUsagePeriod.session);
    expect(level.bucketKey, 'session-root');
    expect(level.totalCount, 4);
    expect(level.sessionCount, 1);
    expect(level.recentEvents.map((event) => event.sessionId).toSet(), <String>{
      'session-root',
    });
    await store.flush();

    final persisted = jsonDecode(await File(storePath).readAsString()) as Map;
    expect((persisted['sessions'] as Map).keys, <Object?>['session-root']);
  });

  test('恢复时合并旧嵌套会话并清理非法周期', () async {
    await File(storePath).writeAsString(
      jsonEncode(<String, Object?>{
        'version': 3,
        'periods': <String, Object?>{
          'day': <String, Object?>{
            '2026-07-17': _bucketJson(1),
            '2026-07-18': _bucketJson(8),
            '2026-99-99': _bucketJson(9),
          },
        },
        'sessions': <String, Object?>{
          'session-root': _bucketJson(1, sessionId: 'session-root'),
          'session-root/agent/agent-1/task/task-1': _bucketJson(
            2,
            sessionId: 'session-root/agent/agent-1/task/task-1',
          ),
        },
        'recent_events': <Object?>[],
      }),
    );
    final store = _store(storePath, now);

    await store.initialize();
    final session = store.sessionSnapshot(
      'session-root/agent/agent-1/task/task-1',
    );
    expect(session?.totalCallCount, 3);
    expect(session?.toolCallCounts, <String, int>{'Read': 3});
    expect(
      store
          .snapshot(
            kind: AiResourceUsageKind.tool,
            preferredSessionId: 'session-root',
          )
          .level(AiResourceUsagePeriod.session)
          .resources
          .single
          .sessionCount,
      1,
    );
    expect(
      store
          .snapshot(kind: AiResourceUsageKind.tool)
          .level(AiResourceUsagePeriod.day)
          .totalCount,
      1,
    );
    await store.flush();

    final persisted = jsonDecode(await File(storePath).readAsString()) as Map;
    expect((persisted['sessions'] as Map).keys, <Object?>['session-root']);
    expect(
      ((persisted['periods'] as Map)['day'] as Map).containsKey('2026-99-99'),
      isFalse,
    );
    expect(
      ((persisted['periods'] as Map)['day'] as Map).containsKey('2026-07-18'),
      isFalse,
    );
  });

  test('复合敏感键会脱敏且控制字符标识会被拒绝', () async {
    final store = _store(storePath, now);
    await store.recordResources(
      sessionId: 'session-1',
      resources: const <AiResourceUsageKind, Iterable<String>>{
        AiResourceUsageKind.hook: <String>['hook-1', 'bad\nidentifier'],
      },
      resultSummary: 'access_token=token-value client_secret: "secret-value"',
    );

    final level = store
        .snapshot(kind: AiResourceUsageKind.hook)
        .level(AiResourceUsagePeriod.session);
    expect(level.counts, <String, int>{'hook-1': 1});
    expect(level.recentEvents.single.resultSummary, contains('[已脱敏]'));
    expect(
      level.recentEvents.single.resultSummary,
      isNot(contains('token-value')),
    );
    expect(
      level.recentEvents.single.resultSummary,
      isNot(contains('secret-value')),
    );
    await store.flush();
  });

  test('损坏的统计文件会自动重建为空状态', () async {
    await File(storePath).writeAsString('{invalid-json');
    final store = _store(storePath, now);

    await store.initialize();
    expect(store.snapshot(kind: AiResourceUsageKind.tool).isEmpty, isTrue);
    await store.flush();

    final persisted = jsonDecode(await File(storePath).readAsString()) as Map;
    expect(persisted['version'], 3);
    expect(persisted['sessions'], isEmpty);
  });

  test('资源迭代器始终按固定预算消费', () async {
    final store = _store(storePath, now);

    await store
        .recordResources(
          sessionId: 'session-1',
          resources: <AiResourceUsageKind, Iterable<String>>{
            AiResourceUsageKind.hook: _infiniteResourceIds(),
          },
        )
        .timeout(const Duration(seconds: 1));

    final level = store
        .snapshot(kind: AiResourceUsageKind.hook)
        .level(AiResourceUsagePeriod.session);
    expect(level.counts, <String, int>{'hook-1': 1});
    await store.flush();
  });
}

AiToolUsagePromotionStore _store(String path, DateTime now) {
  return AiToolUsagePromotionStore(
    filePath: path,
    clock: () => now,
    persistDebounce: const Duration(days: 1),
  );
}

Map<String, Object?> _bucketJson(int count, {String? sessionId}) =>
    <String, Object?>{
      'counts': <String, Object?>{
        'tool': <String, int>{'Read': count},
      },
      'totals': <String, int>{'tool': count},
      if (sessionId != null)
        'metrics': <String, Object?>{
          'tool': <String, Object?>{
            'Read': <String, Object?>{
              'calls': count,
              'successes': count,
              'duration_sample_count': count,
              'session_ids': <String>[sessionId],
            },
          },
        },
    };

Iterable<String> _infiniteResourceIds() sync* {
  while (true) {
    yield 'hook-1';
  }
}
