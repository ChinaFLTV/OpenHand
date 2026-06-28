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

  test('session statistics accepts JSON text and JSON text trend points', () {
    final stats = AiSessionStatistics.fromJson('''
      {
        "total_message_count": "5",
        "assistant_message_count": 2.0,
        "total_prompt_tokens": "100",
        "total_completion_tokens": "25.0",
        "total_tokens": -1,
        "cache_hit_trend_points": "[{\\"turn_index\\":\\"1\\",\\"hit_ratio\\":\\"0.5\\",\\"prompt_tokens\\":\\"80\\",\\"cache_read_tokens\\":\\"40\\",\\"cache_write_tokens\\":\\"10\\",\\"starter_message_id\\":123}]"
      }
    ''');

    expect(stats.totalMessageCount, 5);
    expect(stats.assistantMessageCount, 2);
    expect(stats.totalPromptTokens, 100);
    expect(stats.totalCompletionTokens, 25);
    expect(stats.totalTokens, isNull);
    expect(stats.cacheHitTrendPoints, hasLength(1));
    final point = stats.cacheHitTrendPoints.single;
    expect(point.turnIndex, 1);
    expect(point.hitRatio, 0.5);
    expect(point.promptTokens, 80);
    expect(point.cacheReadTokens, 40);
    expect(point.cacheWriteTokens, 10);
    expect(point.starterMessageId, '123');
  });

  test('session cache hit trend accepts JSON object text', () {
    final point = AiSessionCacheHitTrendPoint.fromJson('''
      {
        "turn_index": "3",
        "hit_ratio": "0.75",
        "prompt_tokens": "120",
        "cache_read_tokens": "90",
        "cache_write_tokens": "30",
        "starter_origin": "user",
        "idle_gap_seconds": "120"
      }
    ''');

    expect(point.turnIndex, 3);
    expect(point.hitRatio, 0.75);
    expect(point.promptTokens, 120);
    expect(point.cacheReadTokens, 90);
    expect(point.cacheWriteTokens, 30);
    expect(point.starterOrigin, 'user');
    expect(point.idleGapSeconds, 120);
  });
}
