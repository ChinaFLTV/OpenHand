import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
