import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('drops stale cache ratio when provider cache usage is absent', () {
    final stats = AiSessionStatistics.fromJson(<String, Object?>{
      'total_prompt_tokens': 1000,
      'cache_hit_ratio': 0.0,
      'cache_hit_trend_points': <Object?>[
        <String, Object?>{
          'turn_index': 2,
          'hit_ratio': 0.0,
          'prompt_tokens': 1000,
          'cache_read_tokens': 0,
          'cache_write_tokens': 0,
        },
      ],
    });

    expect(stats.cacheReadTokens, isNull);
    expect(stats.cacheCreationTokens, isNull);
    expect(stats.cacheHitRatio, isNull);
    expect(stats.cacheHitTrendPoints, isEmpty);
  });

  test('keeps explicit zero cache telemetry', () {
    final stats = AiSessionStatistics.fromJson(<String, Object?>{
      'total_prompt_tokens': 1000,
      'cache_read_tokens': 0,
      'cache_creation_tokens': 0,
      'cache_hit_ratio': 0.0,
      'cache_hit_trend_points': <Object?>[
        <String, Object?>{
          'turn_index': 2,
          'hit_ratio': 0.0,
          'prompt_tokens': 1000,
          'cache_read_tokens': 0,
          'cache_write_tokens': 0,
        },
      ],
    });

    expect(stats.cacheReadTokens, 0);
    expect(stats.cacheCreationTokens, 0);
    expect(stats.cacheHitRatio, 0.0);
    expect(stats.cacheHitTrendPoints, hasLength(1));
  });

  test('invalidates stale zero ratio when cache read tokens exist', () {
    final stats = AiSessionStatistics.fromJson(<String, Object?>{
      'total_prompt_tokens': 16348,
      'cache_read_tokens': 15872,
      'cache_hit_ratio': 0.0,
      'cache_hit_trend_points': <Object?>[
        <String, Object?>{
          'turn_index': 1,
          'hit_ratio': 0.9708832884756545,
          'prompt_tokens': 16348,
          'cache_read_tokens': 15872,
          'cache_write_tokens': 0,
          'starter_origin': 'explicit_user',
        },
      ],
    });

    expect(stats.cacheReadTokens, 15872);
    expect(stats.cacheHitRatio, isNull);
    expect(stats.cacheHitTrendPoints, hasLength(1));
  });
}
