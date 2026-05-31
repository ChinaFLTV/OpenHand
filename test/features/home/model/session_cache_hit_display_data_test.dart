import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';

void main() {
  group('SessionCacheHitTrend.displayData', () {
    test('excludeExtremeMisses removes long-gap zero-hit turns from trend and summary', () {
      final trend = SessionCacheHitTrend.fromSession(
        _buildSession([
          _user('u1', 0),
          _assistant('a1', 1, prompt: 100, cacheRead: 0),
          _user('u2', 2),
          _assistant('a2', 3, prompt: 100, cacheRead: 60),
          _user('u3', 4),
          _assistant(
            'a3',
            5,
            prompt: 100,
            cacheRead: 0,
            metadata: const <String, Object?>{'idle_gap_seconds': 7201},
          ),
        ]),
        claudeStyle: true,
      );

      final filtered = trend.displayData(SessionCacheHitDisplayMode.excludeExtremeMisses);
      final all = trend.displayData(SessionCacheHitDisplayMode.includeAll);

      expect(trend.hasExtremeIdleExpiryMisses, isTrue);
      expect(filtered.excludedPointCount, 1);
      expect(filtered.trend.points.map((point) => point.turnIndex), [1, 2]);
      expect(filtered.averageHitRatio, closeTo(60 / 160, 0.0001));
      expect(filtered.cacheReadTokens, 60);
      expect(filtered.cacheWriteTokens, 0);
      expect(filtered.uncachedPromptTokens, 100);
      expect(all.averageHitRatio, closeTo(60 / 260, 0.0001));
      expect(all.trend.points.map((point) => point.turnIndex), [1, 2, 3]);
    });

    test('includeAll keeps short-gap zero-hit turns in the summary', () {
      final trend = SessionCacheHitTrend.fromSession(
        _buildSession([
          _user('u1', 0),
          _assistant('a1', 1, prompt: 100, cacheRead: 0),
          _user('u2', 2),
          _assistant('a2', 3, prompt: 100, cacheRead: 60),
          _user('u3', 4),
          _assistant(
            'a3',
            5,
            prompt: 100,
            cacheRead: 0,
            metadata: const <String, Object?>{'idle_gap_seconds': 3599},
          ),
        ]),
        claudeStyle: true,
      );

      final filtered = trend.displayData(SessionCacheHitDisplayMode.excludeExtremeMisses);

      expect(trend.hasExtremeIdleExpiryMisses, isFalse);
      expect(filtered.excludedPointCount, 0);
      expect(filtered.trend.points, hasLength(3));
      expect(filtered.averageHitRatio, closeTo(60 / 260, 0.0001));
    });

    test('keeps a turn when tool call telemetry appears before the assistant reply', () {
      final trend = SessionCacheHitTrend.fromSession(
        _buildSession([
          _user('u1', 0),
          AiSessionMessage.toolCall(
            id: 'tool-call-1',
            content: 'tool call',
            createdAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
            metadata: const <String, Object?>{'request_url': 'tool://call'},
          ),
          _assistant('a1', 2, prompt: 100, cacheRead: 50),
          _user('u2', 3),
          _assistant('a2', 4, prompt: 100, cacheRead: 50),
        ]),
        claudeStyle: true,
      );

      expect(trend.points, hasLength(2));
      expect(trend.displayData(SessionCacheHitDisplayMode.excludeExtremeMisses).averageHitRatio,
          closeTo(50 / 150, 0.0001));
    });

    test('ignores assistant placeholders without usage before the real reply', () {
      final trend = SessionCacheHitTrend.fromSession(
        _buildSession([
          _user('u1', 0),
          AiSessionMessage.assistant(
            id: 'a1-placeholder',
            content: 'placeholder',
            createdAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
            modelId: 'demo-model',
          ),
          _assistant('a1', 2, prompt: 100, cacheRead: 50),
          _user('u2', 3),
          _assistant('a2', 4, prompt: 100, cacheRead: 50),
        ]),
        claudeStyle: true,
      );

      expect(trend.points, hasLength(2));
      expect(trend.points.first.cacheReadTokens, 50);
      expect(
        trend.displayData(SessionCacheHitDisplayMode.excludeExtremeMisses).averageHitRatio,
        closeTo(50 / 150, 0.0001),
      );
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
  Map<String, Object?> metadata = const <String, Object?>{},
}) => AiSessionMessage.assistant(
  id: id,
  content: 'assistant $id',
  createdAt: DateTime.utc(2026, 1, 1, 0, 0, second),
  usage: AiTokenUsage(
    promptTokens: prompt,
    cacheReadTokens: cacheRead,
    cacheCreationTokens: 0,
  ),
  metadata: metadata,
);
