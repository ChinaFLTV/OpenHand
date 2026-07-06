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

  test('keeps first cold start as a real model request', () {
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

    expect(display.excludedPointCount, 0);
    expect(display.trend.points, hasLength(1));
    expect(display.averageHitRatio, 0);
  });

  test('excludes only long idle expiry misses from the cleaned view', () {
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
          idleGapSeconds: 3600,
          ttlSuspected: true,
          prefixDriftSuspected: false,
          automaticProviderMissSuspected: false,
        ),
        SessionCacheHitTurnPoint(
          turnIndex: 2,
          starterMessageId: 'tool-1',
          starterMessageKind: 'tool',
          starterOrigin: 'openhand_background',
          timestamp: DateTime.utc(2026, 7, 6, 0, 1),
          hitRatio: 0.9,
          averageHitRatio: 0.9,
          promptTokens: 1000,
          cacheReadTokens: 900,
          cacheWriteTokens: 0,
          idleGapSeconds: 5,
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
    expect(display.trend.points.single.turnIndex, 2);
    expect(display.averageHitRatio, closeTo(0.9, 0.0001));
  });

  test('keeps OpenHand tool continuations as separate model requests', () {
    final startedAt = DateTime.utc(2026, 7, 6);
    final session = _sessionWithMessages(<AiSessionMessage>[
      AiSessionMessage.user(
        id: 'user-1',
        content: 'run it',
        createdAt: startedAt,
      ),
      AiSessionMessage.assistant(
        id: 'assistant-1',
        content: 'calling tool',
        createdAt: startedAt.add(const Duration(seconds: 1)),
        usage: const AiTokenUsage(
          promptTokens: 1000,
          completionTokens: 10,
          totalTokens: 1010,
          cacheReadTokens: 0,
          cacheCreationTokens: 100,
        ),
      ),
      AiSessionMessage.toolResult(
        id: 'tool-1',
        content: 'tool output',
        createdAt: startedAt.add(const Duration(seconds: 2)),
        metadata: const <String, Object?>{},
      ),
      AiSessionMessage.assistant(
        id: 'assistant-2',
        content: 'final',
        createdAt: startedAt.add(const Duration(seconds: 3)),
        usage: const AiTokenUsage(
          promptTokens: 2000,
          completionTokens: 20,
          totalTokens: 2020,
          cacheReadTokens: 1500,
          cacheCreationTokens: 0,
        ),
      ),
    ]);

    final trend = SessionCacheHitTrend.fromSession(session, claudeStyle: false);
    final display = trend.displayData(
      SessionCacheHitDisplayMode.excludeExtremeMisses,
    );

    expect(display.excludedPointCount, 0);
    expect(
      display.trend.points.map((point) => point.starterMessageId),
      <String>['user-1', 'tool-1'],
    );
    expect(
      display.trend.points.last.starterOrigin,
      aiSessionMessageSenderOriginOpenHandBackground,
    );
    expect(display.cacheReadTokens, 1500);
    expect(display.averageHitRatio, closeTo(1500 / 3000, 0.0001));
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
