import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';

void main() {
  group('SessionCacheHitViewport', () {
    test('zooms around anchor and clamps to minimum visible points', () {
      final viewport = SessionCacheHitViewport.full(
        20,
      ).zoomAround(anchor: 10, scale: 2);

      expect(viewport.start, closeTo(5.0, 0.0001));
      expect(viewport.end, closeTo(14.5, 0.0001));
    });

    test('pans inside bounds without overflowing range', () {
      const viewport = SessionCacheHitViewport(
        start: 5,
        end: 10,
        totalPoints: 20,
      );

      expect(viewport.panBy(-10).start, 0);
      expect(viewport.panBy(20).end, 19);
    });
  });

  group('SessionCacheHitTrend.fromSession', () {
    test(
      'aggregates complete user to assistant turns and excludes first turn from average',
      () {
        final session = _buildSession([
          _user('u1', 0),
          _assistant('a1', 1, prompt: 100, cacheRead: 0),
          _assistant('a1-tool', 2, prompt: 20, cacheRead: 0),
          _user('u2', 3),
          _assistant('a2', 4, prompt: 100, cacheRead: 50),
          _reasoning('r2', 5),
          _user('u3', 6),
          _assistant('a3', 7, prompt: 100, cacheRead: 100),
        ]);

        final trend = SessionCacheHitTrend.fromSession(
          session,
          claudeStyle: true,
        );

        expect(trend.points, hasLength(3));
        expect(trend.points.map((e) => e.turnIndex), [1, 2, 3]);
        expect(trend.points[0].hitRatio, closeTo(0, 0.0001));
        expect(trend.points[1].hitRatio, closeTo(50 / 150, 0.0001));
        expect(trend.points[2].hitRatio, closeTo(100 / 200, 0.0001));
        expect(trend.points[0].averageHitRatio, closeTo(0, 0.0001));
        expect(trend.points[1].averageHitRatio, closeTo(50 / 150, 0.0001));
        expect(
          trend.points[2].averageHitRatio,
          closeTo((50 + 100) / (150 + 200), 0.0001),
        );
        expect(
          trend.averageHitRatio,
          closeTo((50 + 100) / (150 + 200), 0.0001),
        );
      },
    );

    test('uses prompt denominator for OpenAI style providers', () {
      final session = _buildSession([
        _user('u1', 0),
        _assistant('a1', 1, prompt: 100, cacheRead: 0),
        _user('u2', 2),
        _assistant('a2', 3, prompt: 100, cacheRead: 40),
        _user('u3', 4),
        _assistant('a3', 5, prompt: 80, cacheRead: 20),
      ]);

      final trend = SessionCacheHitTrend.fromSession(session, claudeStyle: false);

      expect(trend.points[1].hitRatio, closeTo(0.4, 0.0001));
      expect(trend.points[2].hitRatio, closeTo(0.25, 0.0001));
      expect(trend.averageHitRatio, closeTo((40 + 20) / (100 + 80), 0.0001));
    });

    test(
      'ignores deleted and non visible messages and only closes a turn on assistant usage',
      () {
        final session = _buildSession([
          _user('u1', 0),
          _assistant('a1', 1, prompt: 100, cacheRead: 0),
          _user('u2', 2),
          _assistant(
            'deleted',
            3,
            prompt: 200,
            cacheRead: 120,
            isDeleted: true,
          ),
          AiSessionMessage(
            id: 'status-hidden',
            kind: AiSessionMessageKind.status,
            role: AiSessionMessageRole.system,
            content: 'hidden',
            createdAt: DateTime.utc(2026, 1, 1, 0, 0, 4),
            characterCount: 6,
          ),
          _assistant('a2', 5, prompt: 90, cacheRead: 30),
        ]);

        final trend = SessionCacheHitTrend.fromSession(
          session,
          claudeStyle: true,
        );

        expect(trend.points, hasLength(2));
        expect(trend.points[1].hitRatio, closeTo(30 / 120, 0.0001));
      },
    );

    test('marks ttl suspected points from prompt metadata', () {
      final session = _buildSession([
        _user('u1', 0),
        _assistant('a1', 1, prompt: 100, cacheRead: 0),
        _user('u2', 2),
        _assistant(
          'a2',
          3,
          prompt: 100,
          cacheRead: 0,
          metadata: const <String, Object?>{
            'idle_gap_seconds': 7200,
            'ttl_suspected': true,
            'stable_prefix_hash': 'aaaa',
            'previous_stable_prefix_hash': 'aaaa',
            'tool_catalog_hash': 'bbbb',
            'previous_tool_catalog_hash': 'bbbb',
          },
        ),
      ]);

      final trend = SessionCacheHitTrend.fromSession(session, claudeStyle: true);

      expect(trend.points.last.ttlSuspected, isTrue);
      expect(trend.points.last.prefixDriftSuspected, isFalse);
      expect(trend.points.last.missKind, SessionCacheMissKind.ttlSuspected);
    });

    test('marks prefix drift when hashes change without ttl suspicion', () {
      final session = _buildSession([
        _user('u1', 0),
        _assistant('a1', 1, prompt: 100, cacheRead: 0),
        _user('u2', 2),
        _assistant(
          'a2',
          3,
          prompt: 100,
          cacheRead: 0,
          metadata: const <String, Object?>{
            'idle_gap_seconds': 120,
            'ttl_suspected': false,
            'stable_prefix_hash': 'after',
            'previous_stable_prefix_hash': 'before',
            'tool_catalog_hash': 'tool-after',
            'previous_tool_catalog_hash': 'tool-before',
          },
        ),
      ]);

      final trend = SessionCacheHitTrend.fromSession(session, claudeStyle: true);

      expect(trend.points.last.ttlSuspected, isFalse);
      expect(trend.points.last.prefixDriftSuspected, isTrue);
      expect(trend.points.last.missKind, SessionCacheMissKind.prefixDrift);
    });
  });
}

AiSession _buildSession(List<AiSessionMessage> messages) {
  final totalUsage = messages
      .map((message) => message.usage)
      .whereType<AiTokenUsage>()
      .fold(const AiTokenUsage(), (sum, usage) => sum.merge(usage));
  return AiSession(
    id: 'session-1',
    title: 'Demo',
    templateId: 'default',
    templateName: 'Default',
    templateIconName: 'chat',
    templateInternalVersion: '1',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'zh-CN',
      platform: 'macos',
      appVersion: '1.0.0',
      appBuildNumber: '1',
      applicationDirectory: '/',
      homeDirectory: '/',
      settingsFilePath: '/settings.json',
      skillsStoragePath: '/skills',
      mcpServersFilePath: '/mcp.json',
      userMemoryFilePath: '/memory.md',
      sessionsDirectoryPath: '/sessions',
      compressionThresholdChars: 1024,
    ),
    statistics: AiSessionStatistics.fromMessages(
      messages,
      totalPromptCharacters: 0,
      promptBuildCount: 0,
      compressionRunCount: 0,
      totalUsage: totalUsage,
      firstPromptTokens: messages
          .map((message) => message.usage?.promptTokens)
          .whereType<int>()
          .cast<int?>()
          .firstWhere((value) => value != null, orElse: () => null),
      lastPromptSystemMessageCount: 0,
      lastPromptHistoryMessageCount: 0,
    ),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}

AiSessionMessage _user(String id, int second) => AiSessionMessage.user(
  id: id,
  content: 'user $id',
  createdAt: DateTime.utc(2026, 1, 1, 0, 0, second),
);

AiSessionMessage _assistant(
  String id,
  int second, {
  required int prompt,
  required int cacheRead,
  bool isDeleted = false,
  Map<String, Object?> metadata = const <String, Object?>{},
}) => AiSessionMessage.assistant(
  id: id,
  content: 'assistant $id',
  createdAt: DateTime.utc(2026, 1, 1, 0, 0, second),
  usage: AiTokenUsage(promptTokens: prompt, cacheReadTokens: cacheRead),
  metadata: metadata,
).copyWith(isDeleted: isDeleted);

AiSessionMessage _reasoning(String id, int second) =>
    AiSessionMessage.reasoning(
      id: id,
      content: 'thinking',
      createdAt: DateTime.utc(2026, 1, 1, 0, 0, second),
    );
