import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('session statistics ignore non-finite cache hit ratios', () {
    final stats = AiSessionStatistics.fromJson(<String, Object?>{
      'cache_hit_ratio': 'NaN',
      'cache_hit_trend_points': <Object?>[
        <String, Object?>{
          'turn_index': '2',
          'hit_ratio': 'Infinity',
          'prompt_tokens': 'bad',
          'cache_read_tokens': 3.7,
          'cache_write_tokens': -1,
          'idle_gap_seconds': '90',
        },
      ],
    });

    expect(stats.cacheHitRatio, isNull);
    expect(stats.cacheHitTrendPoints, hasLength(1));
    final point = stats.cacheHitTrendPoints.single;
    expect(point.turnIndex, 2);
    expect(point.hitRatio, 0);
    expect(point.promptTokens, 0);
    expect(point.cacheReadTokens, 3);
    expect(point.cacheWriteTokens, 0);
    expect(point.idleGapSeconds, 90);
  });

  test('session cache hit trend clamps finite ratios', () {
    final point = AiSessionCacheHitTrendPoint.fromJson(<String, Object?>{
      'turn_index': 1,
      'hit_ratio': '1.25',
      'prompt_tokens': '100',
      'cache_read_tokens': '25',
      'cache_write_tokens': '5',
      'idle_gap_seconds': double.infinity,
    });

    expect(point.turnIndex, 1);
    expect(point.hitRatio, 1);
    expect(point.promptTokens, 100);
    expect(point.cacheReadTokens, 25);
    expect(point.cacheWriteTokens, 5);
    expect(point.idleGapSeconds, isNull);
  });
}
