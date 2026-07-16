import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';

void main() {
  final now = DateTime.utc(2026, 7, 16, 12);

  test('用户轮次直接定位用户消息', () {
    final session = _session(<AiSessionMessage>[
      AiSessionMessage.user(id: 'user-1', content: '开始', createdAt: now),
      AiSessionMessage.assistant(
        id: 'assistant-1',
        content: '收到',
        createdAt: now.add(const Duration(seconds: 1)),
      ),
    ]);

    expect(session.transcriptAnchorForRoundStarter('user-1')?.id, 'user-1');
  });

  test('工具与 MCP 结果轮次定位到配对工具卡片', () {
    final session = _session(<AiSessionMessage>[
      AiSessionMessage.toolCall(
        id: 'call-card',
        content: 'ToolSearch({})',
        createdAt: now,
        metadata: const <String, Object?>{
          'tool_call_id': 'call-1',
          'tool_name': 'ToolSearch',
        },
      ),
      AiSessionMessage.mcpResult(
        id: 'mcp-result',
        content: '搜索结果',
        createdAt: now.add(const Duration(seconds: 1)),
        metadata: const <String, Object?>{
          'tool_call_id': 'call-1',
          'tool_name': 'ToolSearch',
        },
      ),
    ]);

    expect(session.displayMessages.map((message) => message.id), <String>[
      'call-card',
    ]);
    expect(
      session.transcriptAnchorForRoundStarter('mcp-result')?.id,
      'call-card',
    );
  });

  test('不可展示的轮次起点回退到同轮首条可见消息', () {
    final session = _session(<AiSessionMessage>[
      AiSessionMessage(
        id: 'empty-tool-result',
        kind: AiSessionMessageKind.mcp,
        role: AiSessionMessageRole.tool,
        content: '',
        createdAt: now,
        characterCount: 0,
      ),
      AiSessionMessage.assistant(
        id: 'assistant-1',
        content: '继续执行',
        createdAt: now.add(const Duration(seconds: 1)),
      ),
      AiSessionMessage.user(
        id: 'user-2',
        content: '下一轮',
        createdAt: now.add(const Duration(seconds: 2)),
      ),
    ]);

    expect(
      session.transcriptAnchorForRoundStarter('empty-tool-result')?.id,
      'assistant-1',
    );
  });

  test('已删除或不存在的轮次不会跳到其他消息', () {
    final session = _session(<AiSessionMessage>[
      AiSessionMessage(
        id: 'deleted-user',
        kind: AiSessionMessageKind.user,
        role: AiSessionMessageRole.user,
        content: '已删除',
        createdAt: now,
        characterCount: 3,
        isDeleted: true,
      ),
      AiSessionMessage.assistant(
        id: 'assistant-1',
        content: '不应定位到这里',
        createdAt: now.add(const Duration(seconds: 1)),
      ),
    ]);

    expect(session.transcriptAnchorForRoundStarter('deleted-user'), isNull);
    expect(session.transcriptAnchorForRoundStarter('missing'), isNull);
  });

  test('缓存趋势锚点支持持久化往返', () {
    const point = AiSessionCacheHitTrendPoint(
      turnIndex: 4,
      hitRatio: 0.98,
      promptTokens: 1000,
      cacheReadTokens: 980,
      cacheWriteTokens: 0,
      starterMessageId: 'mcp-result',
      starterMessageKind: 'mcp',
      starterOrigin: 'openhand_background',
      anchorMessageId: 'call-card',
    );

    final restored = AiSessionCacheHitTrendPoint.fromJson(point.toJson());
    expect(restored.anchorMessageId, 'call-card');
  });

  test('缓存趋势为后台工具轮次写入可见锚点', () {
    final session = _session(<AiSessionMessage>[
      AiSessionMessage.user(id: 'user-1', content: '开始', createdAt: now),
      AiSessionMessage.toolCall(
        id: 'call-card',
        content: 'ToolSearch({})',
        createdAt: now.add(const Duration(seconds: 1)),
        metadata: const <String, Object?>{
          'tool_call_id': 'call-1',
          'tool_name': 'ToolSearch',
        },
      ),
      AiSessionMessage(
        id: 'mcp-result',
        kind: AiSessionMessageKind.mcp,
        role: AiSessionMessageRole.tool,
        content: '搜索结果',
        createdAt: now.add(const Duration(seconds: 2)),
        characterCount: 4,
        usage: const AiTokenUsage(promptTokens: 1000, cacheReadTokens: 900),
        metadata: const <String, Object?>{
          'tool_call_id': 'call-1',
          'tool_name': 'ToolSearch',
        },
      ),
      AiSessionMessage.assistant(
        id: 'assistant-1',
        content: '继续执行',
        createdAt: now.add(const Duration(seconds: 3)),
        usage: const AiTokenUsage(promptTokens: 1000, cacheReadTokens: 900),
      ),
    ]);

    final trend = SessionCacheHitTrend.fromSession(session, claudeStyle: false);
    final point = trend.points.single;
    expect(point.starterMessageId, 'mcp-result');
    expect(point.anchorMessageId, 'call-card');
  });
}

AiSession _session(List<AiSessionMessage> messages) {
  final now = DateTime.utc(2026, 7, 16, 12);
  return AiSession(
    id: 'session-1',
    title: '定位测试',
    templateId: 'default',
    templateName: '默认助手',
    templateIconName: 'chat',
    templateInternalVersion: '1',
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: AiSessionEnvironment(
      localeTag: 'zh-Hans',
      platform: 'test',
      appVersion: 'test',
      appBuildNumber: '1',
      applicationDirectory: '',
      homeDirectory: '',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      sessionsDirectoryPath: '',
      compressionThresholdChars: 100000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}
