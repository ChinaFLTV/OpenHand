import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';

void main() {
  group('SessionCacheHitTrend', () {
    test('marks ttl suspected points from prompt metadata', () {
      final session = _sessionWithAssistantMetadata(<String, Object?>{
        'idle_gap_seconds': 7200,
        'ttl_suspected': true,
        'stable_prefix_hash': 'aaaa',
        'previous_stable_prefix_hash': 'aaaa',
        'tool_catalog_hash': 'bbbb',
        'previous_tool_catalog_hash': 'bbbb',
      });

      final trend = SessionCacheHitTrend.fromSession(session, claudeStyle: true);
      expect(trend.points.last.ttlSuspected, isTrue);
      expect(trend.points.last.prefixDriftSuspected, isFalse);
      expect(trend.points.last.missKind, SessionCacheMissKind.ttlSuspected);
    });

    test('marks prefix drift when hashes change without ttl suspicion', () {
      final session = _sessionWithAssistantMetadata(<String, Object?>{
        'idle_gap_seconds': 120,
        'ttl_suspected': false,
        'stable_prefix_hash': 'after',
        'previous_stable_prefix_hash': 'before',
        'tool_catalog_hash': 'tool-after',
        'previous_tool_catalog_hash': 'tool-before',
      });

      final trend = SessionCacheHitTrend.fromSession(session, claudeStyle: true);
      expect(trend.points.last.ttlSuspected, isFalse);
      expect(trend.points.last.prefixDriftSuspected, isTrue);
      expect(trend.points.last.missKind, SessionCacheMissKind.prefixDrift);
    });
  });
}

AiSession _sessionWithAssistantMetadata(
  Map<String, Object?> assistantMetadata, {
  int cacheReadTokens = 0,
}) {
  final now = DateTime.utc(2026, 1, 1, 12);
  return AiSession(
    id: 's1',
    title: 'session',
    templateId: 'default',
    templateName: 'Default',
    templateIconName: 'auto_awesome_rounded',
    templateInternalVersion: '1.0.0',
    createdAt: now,
    updatedAt: now,
    environment: const AiSessionEnvironment(
      localeTag: 'zh-CN',
      platform: 'macos',
      appVersion: '1.0.0',
      appBuildNumber: '1',
      applicationDirectory: '/app',
      homeDirectory: '/home',
      settingsFilePath: '/tmp/settings.json',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.json',
      sessionsDirectoryPath: '/tmp/sessions',
      compressionThresholdChars: 1000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
    messages: <AiSessionMessage>[
      AiSessionMessage.user(
        id: 'u1',
        content: 'hi',
        createdAt: now,
      ),
      AiSessionMessage.assistant(
        id: 'a1',
        content: 'hello',
        createdAt: now.add(const Duration(seconds: 1)),
        usage: AiTokenUsage(
          promptTokens: 100,
          completionTokens: 10,
          cacheReadTokens: cacheReadTokens,
        ),
        metadata: assistantMetadata,
      ),
      AiSessionMessage.user(
        id: 'u2',
        content: 'next',
        createdAt: now.add(const Duration(seconds: 2)),
      ),
      AiSessionMessage.assistant(
        id: 'a2',
        content: 'next reply',
        createdAt: now.add(const Duration(seconds: 3)),
        usage: AiTokenUsage(
          promptTokens: 100,
          completionTokens: 10,
          cacheReadTokens: cacheReadTokens,
        ),
        metadata: assistantMetadata,
      ),
    ],
  );
}
