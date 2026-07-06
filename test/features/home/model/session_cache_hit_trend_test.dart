import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/home/index.dart';

void main() {
  test('keeps first round when it has real cache hits', () {
    final trend = SessionCacheHitTrend(
      claudeStyle: false,
      averageHitRatio: 0,
      points: <SessionCacheHitTurnPoint>[
        SessionCacheHitTurnPoint(
          turnIndex: 1,
          starterMessageId: 'user-1',
          starterMessageKind: 'user',
          starterOrigin: 'explicit_user',
          timestamp: DateTime.utc(2026, 7, 6),
          hitRatio: 15872 / 16348,
          averageHitRatio: 15872 / 16348,
          promptTokens: 16348,
          cacheReadTokens: 15872,
          cacheWriteTokens: 0,
          idleGapSeconds: null,
          ttlSuspected: false,
          prefixDriftSuspected: false,
          automaticProviderMissSuspected: false,
        ),
      ],
    );

    final display = trend.displayData(
      SessionCacheHitDisplayMode.excludeExtremeMisses,
    );

    expect(display.excludedPointCount, 0);
    expect(display.cacheReadTokens, 15872);
    expect(display.averageHitRatio, greaterThan(0.97));
  });

  test('excludes first round only when it is a true cold start', () {
    final trend = SessionCacheHitTrend(
      claudeStyle: false,
      averageHitRatio: 0,
      points: <SessionCacheHitTurnPoint>[
        SessionCacheHitTurnPoint(
          turnIndex: 1,
          starterMessageId: 'user-1',
          starterMessageKind: 'user',
          starterOrigin: 'explicit_user',
          timestamp: DateTime.utc(2026, 7, 6),
          hitRatio: 0,
          averageHitRatio: 0,
          promptTokens: 1000,
          cacheReadTokens: 0,
          cacheWriteTokens: 0,
          idleGapSeconds: null,
          ttlSuspected: false,
          prefixDriftSuspected: false,
          automaticProviderMissSuspected: false,
        ),
      ],
    );

    final display = trend.displayData(
      SessionCacheHitDisplayMode.excludeExtremeMisses,
    );

    expect(display.excludedPointCount, 1);
    expect(display.trend.points, isEmpty);
    expect(display.averageHitRatio, 0);
  });

  test(
    'treats missing cache fields as zero after provider support is known',
    () {
      final startedAt = DateTime.utc(2026, 7, 6);
      final session = _sessionWithMessages(<AiSessionMessage>[
        AiSessionMessage.user(
          id: 'user-1',
          content: 'one',
          createdAt: startedAt,
        ),
        AiSessionMessage.assistant(
          id: 'assistant-1',
          content: 'reply',
          createdAt: startedAt.add(const Duration(seconds: 1)),
          usage: const AiTokenUsage(
            promptTokens: 16348,
            completionTokens: 1,
            totalTokens: 16349,
            cacheReadTokens: 15872,
          ),
        ),
        AiSessionMessage.user(
          id: 'user-2',
          content: 'two',
          createdAt: startedAt.add(const Duration(seconds: 2)),
        ),
        AiSessionMessage.assistant(
          id: 'assistant-2',
          content: 'reply',
          createdAt: startedAt.add(const Duration(seconds: 3)),
          usage: const AiTokenUsage(
            promptTokens: 16393,
            completionTokens: 1,
            totalTokens: 16394,
          ),
        ),
      ]);

      final trend = SessionCacheHitTrend.fromSession(
        session,
        claudeStyle: false,
      );
      final display = trend.displayData(
        SessionCacheHitDisplayMode.excludeExtremeMisses,
      );

      expect(trend.points, hasLength(2));
      expect(display.cacheReadTokens, 15872);
      expect(display.uncachedPromptTokens, 16869);
      expect(display.averageHitRatio, closeTo(15872 / 32741, 0.0001));
    },
  );
}

AiSession _sessionWithMessages(List<AiSessionMessage> messages) {
  final now = DateTime.utc(2026, 7, 6);
  return AiSession(
    id: 'session-1',
    title: 'test',
    templateId: 'default',
    templateName: 'Default',
    templateIconName: 'auto',
    templateInternalVersion: '1',
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: AiSessionEnvironment(
      localeTag: 'zh',
      platform: 'macOS',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '/tmp',
      homeDirectory: '/tmp',
      settingsFilePath: 'db://settings',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.json',
      sessionsDirectoryPath: '/tmp/sessions',
      compressionThresholdChars: 0,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}
