import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';

void main() {
  group('SessionCacheHitTrend diagnostics', () {
    test(
      'classifies short stable zero hit as OpenAI-compatible auto-cache miss',
      () {
        final session = _sessionWithTwoTurns(
          secondAssistantMetadata: _cacheMetadata(
            idleGapSeconds: 93,
            stablePrefixHash: 'stable',
            previousStablePrefixHash: 'stable',
            toolCatalogHash: 'tools',
            previousToolCatalogHash: 'tools',
            cacheControlMarkerCount: 0,
          ),
          secondUsage: const AiTokenUsage(
            promptTokens: 10000,
            completionTokens: 10,
            totalTokens: 10010,
            cacheReadTokens: 0,
          ),
        );

        final trend = SessionCacheHitTrend.fromSession(
          session,
          claudeStyle: false,
        );

        expect(trend.points, hasLength(2));
        expect(trend.points.last.prefixDriftSuspected, isFalse);
        expect(trend.points.last.ttlSuspected, isFalse);
        expect(trend.points.last.providerAutomaticMissSuspected, isTrue);
        expect(
          trend.points.last.missKind,
          SessionCacheMissKind.providerAutomaticMiss,
        );
      },
    );

    test('does not treat partial OpenAI-compatible hits as prefix drift', () {
      final session = _sessionWithTwoTurns(
        secondAssistantMetadata: _cacheMetadata(
          idleGapSeconds: 80,
          stablePrefixHash: 'stable',
          previousStablePrefixHash: 'stable',
          toolCatalogHash: 'tools',
          previousToolCatalogHash: 'tools',
          cacheControlMarkerCount: 0,
        ),
        secondUsage: const AiTokenUsage(
          promptTokens: 10000,
          completionTokens: 10,
          totalTokens: 10010,
          cacheReadTokens: 7000,
        ),
      );

      final trend = SessionCacheHitTrend.fromSession(
        session,
        claudeStyle: false,
      );

      expect(trend.points, hasLength(2));
      expect(trend.points.last.prefixDriftSuspected, isFalse);
      expect(trend.points.last.ttlSuspected, isTrue);
      expect(trend.points.last.providerAutomaticMissSuspected, isFalse);
      expect(trend.points.last.missKind, SessionCacheMissKind.ttlSuspected);
    });

    test('keeps cache_control drift detection for Claude-style cache', () {
      final session = _sessionWithTwoTurns(
        secondAssistantMetadata: _cacheMetadata(
          idleGapSeconds: 10,
          stablePrefixHash: 'stable',
          previousStablePrefixHash: 'stable',
          toolCatalogHash: 'tools',
          previousToolCatalogHash: 'tools',
          cacheControlMarkerCount: 0,
        ),
        secondUsage: const AiTokenUsage(
          promptTokens: 3000,
          completionTokens: 10,
          totalTokens: 3010,
          cacheReadTokens: 1000,
        ),
      );

      final trend = SessionCacheHitTrend.fromSession(
        session,
        claudeStyle: true,
      );

      expect(trend.points, hasLength(2));
      expect(trend.points.last.ttlSuspected, isFalse);
      expect(trend.points.last.prefixDriftSuspected, isTrue);
      expect(trend.points.last.providerAutomaticMissSuspected, isFalse);
      expect(trend.points.last.missKind, SessionCacheMissKind.prefixDrift);
    });
  });
}

Map<String, Object?> _cacheMetadata({
  required int idleGapSeconds,
  required String stablePrefixHash,
  required String previousStablePrefixHash,
  required String toolCatalogHash,
  required String previousToolCatalogHash,
  required int cacheControlMarkerCount,
}) {
  return <String, Object?>{
    'request_cache_control_marker_count': cacheControlMarkerCount,
    'prompt_metadata': <String, Object?>{
      'cache_enabled': true,
      'idle_gap_seconds': idleGapSeconds,
      'ttl_suspected': false,
      'stable_prefix_hash': stablePrefixHash,
      'previous_stable_prefix_hash': previousStablePrefixHash,
      'tool_catalog_hash': toolCatalogHash,
      'previous_tool_catalog_hash': previousToolCatalogHash,
    },
  };
}

AiSession _sessionWithTwoTurns({
  required Map<String, Object?> secondAssistantMetadata,
  required AiTokenUsage secondUsage,
}) {
  final now = DateTime.utc(2026, 6, 16);
  return AiSession(
    id: 's1',
    title: 'test',
    templateId: 'default',
    templateName: 'Default',
    templateIconName: 'auto_awesome_rounded',
    templateInternalVersion: '1.0.0',
    createdAt: now,
    updatedAt: now.add(const Duration(seconds: 90)),
    messages: <AiSessionMessage>[
      AiSessionMessage.user(id: 'u1', content: '泥嚎', createdAt: now),
      AiSessionMessage.assistant(
        id: 'a1',
        content: '你好',
        createdAt: now.add(const Duration(seconds: 1)),
        usage: const AiTokenUsage(
          promptTokens: 10000,
          completionTokens: 10,
          totalTokens: 10010,
          cacheReadTokens: 0,
        ),
      ),
      AiSessionMessage.user(
        id: 'u2',
        content: '想你了',
        createdAt: now.add(const Duration(seconds: 80)),
      ),
      AiSessionMessage.assistant(
        id: 'a2',
        content: '我在',
        createdAt: now.add(const Duration(seconds: 81)),
        usage: secondUsage,
        metadata: secondAssistantMetadata,
      ),
    ],
    environment: const AiSessionEnvironment(
      localeTag: 'zh-Hans',
      platform: 'macos',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '/tmp/openhand',
      homeDirectory: '/tmp',
      settingsFilePath: '/tmp/settings.json',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.json',
      sessionsDirectoryPath: '/tmp/sessions',
      compressionThresholdChars: 100000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}
