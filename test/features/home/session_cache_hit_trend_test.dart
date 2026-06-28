import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';
import 'package:openhand/features/home/widgets/token_popup_cache_hit_trend_chart.dart';

void main() {
  test('cleaned trend keeps the second round as a drawable single point', () {
    final now = DateTime.utc(2026, 6, 28, 10);
    final trend = SessionCacheHitTrend(
      claudeStyle: false,
      averageHitRatio: 0.5,
      points: <SessionCacheHitTurnPoint>[
        SessionCacheHitTurnPoint(
          turnIndex: 1,
          starterMessageId: 'user-1',
          starterMessageKind: 'user',
          starterOrigin: 'explicit_user',
          timestamp: now,
          hitRatio: 0.0,
          averageHitRatio: 0.0,
          promptTokens: 16562,
          cacheReadTokens: 2,
          cacheWriteTokens: 0,
          idleGapSeconds: null,
          ttlSuspected: false,
          prefixDriftSuspected: false,
          automaticProviderMissSuspected: false,
        ),
        SessionCacheHitTurnPoint(
          turnIndex: 2,
          starterMessageId: 'user-2',
          starterMessageKind: 'user',
          starterOrigin: 'explicit_user',
          timestamp: now.add(const Duration(seconds: 45)),
          hitRatio: 0.996,
          averageHitRatio: 0.996,
          promptTokens: 16621,
          cacheReadTokens: 16560,
          cacheWriteTokens: 0,
          idleGapSeconds: 44,
          ttlSuspected: false,
          prefixDriftSuspected: false,
          automaticProviderMissSuspected: false,
        ),
      ],
    );

    final displayData = trend.displayData(
      SessionCacheHitDisplayMode.excludeExtremeMisses,
    );

    expect(displayData.trend.points, hasLength(1));
    expect(displayData.trend.points.single.turnIndex, 2);
    expect(displayData.averageHitRatio, greaterThan(0.99));
  });

  test('single-point cache hit trend is centered in the chart area', () {
    const chart = Rect.fromLTWH(10, 20, 100, 50);

    final points = tokenPopupCacheHitTrendAnimatedPolyline(
      ratios: const <double>[1],
      chartRect: chart,
      progress: 1,
    );

    expect(points, hasLength(1));
    expect(points.single.dx, chart.center.dx);
    expect(points.single.dy, chart.top);
  });

  test('stable best-effort automatic cache miss is diagnosed explicitly', () {
    final now = DateTime.utc(2026, 6, 28, 10);
    final session = AiSession(
      id: 'session-1',
      title: 'Cache miss',
      templateId: 'default',
      templateName: 'Default Assistant',
      templateIconName: 'auto_awesome_rounded',
      templateInternalVersion: '3.0.0',
      createdAt: now,
      updatedAt: now.add(const Duration(minutes: 1)),
      environment: const AiSessionEnvironment(
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
      messages: <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'user-1',
          content: 'one',
          createdAt: now,
        ).copyWith(
          usage: const AiTokenUsage(promptTokens: 16000, cacheReadTokens: 2),
        ),
        AiSessionMessage.assistant(
          id: 'assistant-1',
          content: 'reply',
          createdAt: now.add(const Duration(seconds: 1)),
          usage: const AiTokenUsage(promptTokens: 16000, cacheReadTokens: 2),
        ),
        AiSessionMessage.user(
          id: 'user-2',
          content: 'two',
          createdAt: now.add(const Duration(seconds: 40)),
          metadata: _bestEffortPromptMetadata(idleGapSeconds: 40),
        ).copyWith(
          usage: const AiTokenUsage(promptTokens: 16100, cacheReadTokens: 2),
        ),
        AiSessionMessage.assistant(
          id: 'assistant-2',
          content: 'reply',
          createdAt: now.add(const Duration(seconds: 41)),
          usage: const AiTokenUsage(promptTokens: 16100, cacheReadTokens: 2),
          metadata: _bestEffortPromptMetadata(idleGapSeconds: 40),
        ),
      ],
    );

    final trend = SessionCacheHitTrend.fromSession(session, claudeStyle: false);

    expect(trend.points, hasLength(2));
    expect(trend.points.last.prefixDriftSuspected, isFalse);
    expect(trend.points.last.automaticProviderMissSuspected, isTrue);
  });
}

Map<String, Object?> _bestEffortPromptMetadata({required int idleGapSeconds}) {
  return <String, Object?>{
    'stable_prefix_hash': 'stable',
    'previous_stable_prefix_hash': 'stable',
    'tool_catalog_hash': 'tools',
    'previous_tool_catalog_hash': 'tools',
    'cache_enabled': true,
    'cache_control_strategy': 'automatic_provider_cache',
    'cache_provider_automatic_cache_protected': false,
    'cache_provider_automatic_cache_best_effort': true,
    'cache_affinity_enabled': true,
    'cache_affinity_strategy': 'grok_compatible_gateway',
    'request_cache_affinity_marker_count': 2,
    'request_payload_prefix_continuity': true,
    'request_payload_prefix_probe_complete': true,
    'idle_gap_seconds': idleGapSeconds,
    'ttl_suspected': false,
  };
}
