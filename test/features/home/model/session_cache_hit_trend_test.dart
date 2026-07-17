import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';

void main() {
  final createdAt = DateTime.utc(2026, 7, 18);

  AiSession session({
    required AiSessionStatistics statistics,
    List<AiSessionMessage> messages = const <AiSessionMessage>[],
    AiSessionMessageLoadState loadState = AiSessionMessageLoadState.header,
    int messageTotalCount = 2,
  }) {
    return AiSession(
      id: 'session',
      title: '测试会话',
      templateId: 'default',
      templateName: '默认助手',
      templateIconName: '',
      templateInternalVersion: '1',
      createdAt: createdAt,
      updatedAt: createdAt,
      messages: messages,
      environment: AiSessionEnvironment.fromJson(const <String, Object?>{}),
      statistics: statistics,
      recentErrors: const <AiSessionErrorRecord>[],
      messageLoadState: loadState,
      messageTotalCount: messageTotalCount,
    );
  }

  AiSessionStatistics statistics({
    required int totalMessageCount,
    required bool currentSchema,
  }) {
    return AiSessionStatistics.fromJson(<String, Object?>{
      'total_message_count': totalMessageCount,
      'cache_read_tokens': 3328,
      'cache_creation_tokens': 0,
      'cache_hit_ratio': 0,
      'cache_hit_trend_points': currentSchema
          ? <Object?>[
              <String, Object?>{
                'turn_index': 1,
                'hit_ratio': 0,
                'prompt_tokens': 17628,
                'cache_read_tokens': 0,
                'cache_write_tokens': 0,
                'starter_message_id': 'user-1',
                'starter_message_kind': 'user',
                'starter_origin': 'explicit_user',
                'anchor_message_id': 'user-1',
              },
            ]
          : const <Object?>[],
    });
  }

  test('已有新版缓存趋势时不重复回填零命中率', () {
    final value = session(
      statistics: statistics(totalMessageCount: 2, currentSchema: true),
    );

    expect(SessionCacheHitTrend.statisticsNeedHydration(value), isFalse);
  });

  test('旧版缓存统计与不完整窗口仍会回填', () {
    final legacy = session(
      statistics: statistics(totalMessageCount: 2, currentSchema: false),
    );
    final windowed = session(
      statistics: statistics(totalMessageCount: 1, currentSchema: true),
      loadState: AiSessionMessageLoadState.windowed,
    );

    expect(SessionCacheHitTrend.statisticsNeedHydration(legacy), isTrue);
    expect(SessionCacheHitTrend.statisticsNeedHydration(windowed), isTrue);
  });

  test('缓存趋势按会话轮次线性生成并保留间隔', () {
    final messages = <AiSessionMessage>[
      AiSessionMessage.user(id: 'user-1', content: '第一轮', createdAt: createdAt),
      AiSessionMessage.assistant(
        id: 'assistant-1',
        content: '回答一',
        createdAt: createdAt.add(const Duration(seconds: 1)),
        usage: const AiTokenUsage(
          promptTokens: 100,
          cacheCreationTokens: 0,
          cacheReadTokens: 0,
        ),
      ),
      AiSessionMessage.user(
        id: 'user-2',
        content: '第二轮',
        createdAt: createdAt.add(const Duration(seconds: 60)),
      ),
      AiSessionMessage.assistant(
        id: 'assistant-2',
        content: '回答二',
        createdAt: createdAt.add(const Duration(seconds: 61)),
        usage: const AiTokenUsage(
          promptTokens: 100,
          cacheCreationTokens: 0,
          cacheReadTokens: 50,
        ),
      ),
    ];
    final value = session(
      statistics: const AiSessionStatistics.initial(),
      messages: messages,
      loadState: AiSessionMessageLoadState.complete,
      messageTotalCount: messages.length,
    );

    final trend = SessionCacheHitTrend.fromSession(value, claudeStyle: false);

    expect(trend.points, hasLength(2));
    expect(trend.points.last.starterMessageId, 'user-2');
    expect(trend.points.last.anchorMessageId, 'user-2');
    expect(trend.points.last.idleGapSeconds, 60);
  });
}
