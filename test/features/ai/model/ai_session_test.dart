import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';

void main() {
  test('AiSession clamps negative message window indexes', () {
    final session = _session(
      messageWindowStartIndex: -8,
      messageTotalCount: -3,
    );

    expect(session.messageWindowStartIndex, 0);
    expect(session.messageTotalCount, 0);
  });

  test('AiSession keeps total message count at least loaded count', () {
    final now = DateTime.utc(2026);
    final session = _session(
      messages: <AiSessionMessage>[
        AiSessionMessage.user(id: 'user-1', content: 'Hi', createdAt: now),
        AiSessionMessage.assistant(
          id: 'assistant-1',
          content: 'Hello',
          createdAt: now,
        ),
      ],
      messageTotalCount: 1,
    );

    expect(session.messageTotalCount, 2);
  });

  test('AiSessionStatistics clamps cache hit ratio metadata', () {
    expect(
      AiSessionStatistics.fromJson(const <String, Object?>{
        'cache_hit_ratio': -0.25,
      }).cacheHitRatio,
      0,
    );
    expect(
      AiSessionStatistics.fromJson(const <String, Object?>{
        'cache_hit_ratio': '0.42',
      }).cacheHitRatio,
      0.42,
    );
    expect(
      AiSessionStatistics.fromJson(const <String, Object?>{
        'cache_hit_ratio': 1.25,
      }).cacheHitRatio,
      1,
    );
    expect(
      AiSessionStatistics.fromJson(const <String, Object?>{
        'cache_hit_ratio': 'bad',
      }).cacheHitRatio,
      isNull,
    );
  });

  test('AiSessionCacheHitTrendPoint clamps hit ratio metadata', () {
    expect(_trendPointWithHitRatio(-0.25).hitRatio, 0);
    expect(_trendPointWithHitRatio('0.42').hitRatio, 0.42);
    expect(_trendPointWithHitRatio(1.25).hitRatio, 1);
    expect(_trendPointWithHitRatio('bad').hitRatio, 0);
  });

  test('AiSessionEnvironment normalizes tool call safety limits', () {
    final environment = AiSessionEnvironment.fromJson(const <String, Object?>{
      'single_round_tool_call_limit': 999999,
      'sequential_tool_round_limit': -1,
    });

    expect(
      environment.singleRoundToolCallLimit,
      AiSessionEnvironment.maxSingleRoundToolCallLimit,
    );
    expect(
      environment.sequentialToolRoundLimit,
      AiSessionEnvironment.defaultSequentialToolRoundLimit,
    );

    final copied = environment.copyWith(
      singleRoundToolCallLimit: 0,
      sequentialToolRoundLimit: 999999,
    );

    expect(
      copied.singleRoundToolCallLimit,
      AiSessionEnvironment.defaultSingleRoundToolCallLimit,
    );
    expect(
      copied.sequentialToolRoundLimit,
      AiSessionEnvironment.maxSequentialToolRoundLimit,
    );
    expect(
      copied.toJson()['single_round_tool_call_limit'],
      AiSessionEnvironment.defaultSingleRoundToolCallLimit,
    );
    expect(
      copied.toJson()['sequential_tool_round_limit'],
      AiSessionEnvironment.maxSequentialToolRoundLimit,
    );
  });
}

AiSessionCacheHitTrendPoint _trendPointWithHitRatio(Object? hitRatio) {
  return AiSessionCacheHitTrendPoint.fromJson(<String, Object?>{
    AiSessionCacheHitTrendPoint.turnIndexJsonKey: 0,
    AiSessionCacheHitTrendPoint.hitRatioJsonKey: hitRatio,
    AiSessionCacheHitTrendPoint.promptTokensJsonKey: 100,
    AiSessionCacheHitTrendPoint.cacheReadTokensJsonKey: 25,
    AiSessionCacheHitTrendPoint.cacheWriteTokensJsonKey: 0,
  });
}

AiSession _session({
  List<AiSessionMessage> messages = const <AiSessionMessage>[],
  int? messageWindowStartIndex,
  int? messageTotalCount,
}) {
  final now = DateTime.utc(2026);
  return AiSession(
    id: 'session-1',
    title: 'Session',
    templateId: 'template',
    templateName: 'Template',
    templateIconName: 'message',
    templateInternalVersion: '1',
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: _testEnvironment,
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
    messageWindowStartIndex: messageWindowStartIndex,
    messageTotalCount: messageTotalCount,
  );
}

final AiSessionEnvironment _testEnvironment = AiSessionEnvironment(
  localeTag: 'en',
  platform: 'test',
  appVersion: '1.0.0',
  appBuildNumber: '1',
  applicationDirectory: '',
  homeDirectory: '',
  settingsFilePath: '',
  skillsStoragePath: '',
  mcpServersFilePath: '',
  userMemoryFilePath: '',
  sessionsDirectoryPath: '',
  compressionThresholdChars: 0,
);
