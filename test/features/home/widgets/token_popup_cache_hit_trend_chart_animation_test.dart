import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/widgets/token_popup_cache_hit_trend_chart.dart';

void main() {
  test('uses eased animation progress instead of raw linear progress', () {
    expect(tokenPopupCacheHitTrendAnimationProgress(0), 0);
    expect(tokenPopupCacheHitTrendAnimationProgress(1), 1);
    expect(tokenPopupCacheHitTrendAnimationProgress(0.5), greaterThan(0.5));
  });

  test('builds a polyline with an interpolated tail point at mid progress', () {
    final points = tokenPopupCacheHitTrendAnimatedPolyline(
      ratios: const [0.2, 0.8, 0.2],
      chartRect: const Rect.fromLTWH(0, 0, 100, 100),
      progress: 0.5,
    );

    expect(points.length, 3);
    expect(points.last.dx, greaterThan(50));
    expect(points.last.dx, lessThan(100));
    expect(points.last.dy, greaterThan(20));
    expect(points.last.dy, lessThan(80));
  });
}
