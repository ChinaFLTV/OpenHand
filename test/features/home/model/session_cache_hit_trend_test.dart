import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';

void main() {
  group('SessionCacheHitViewport.zoomAround', () {
    test('keeps anchors before the range on the leading edge', () {
      final viewport = const SessionCacheHitViewport(
        start: 10,
        end: 30,
        totalPoints: 60,
      ).zoomAround(anchor: 5, scale: 2);

      expect(viewport.start, 5);
      expect(viewport.end, 15);
    });

    test('keeps anchors after the range on the trailing edge', () {
      final viewport = const SessionCacheHitViewport(
        start: 10,
        end: 30,
        totalPoints: 60,
      ).zoomAround(anchor: 35, scale: 2);

      expect(viewport.start, 25);
      expect(viewport.end, 35);
    });

    test('treats invalid scale as a no-op scale', () {
      final viewport = const SessionCacheHitViewport(
        start: 10,
        end: 30,
        totalPoints: 60,
      ).zoomAround(anchor: 20, scale: 0);

      expect(viewport.start, 10);
      expect(viewport.end, 30);
    });
  });
}
