import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test(
    'web search telemetry parses string values and drops invalid counts',
    () {
      final call = WebSearchCallLog.fromJson(<String, Object?>{
        'timestamp_ms': '1000',
        'query': 'openhand',
        'cache_status': 'hit',
        'success': true,
        'total_duration_ms': '42',
        'merged_hit_count': '-3',
        'fallback_used': false,
        'summary_chars': double.infinity,
        'per_engine': <Object?>[
          <String, Object?>{
            'kind': AiWebSearchEngineKind.tavily.name,
            'success': true,
            'hit_count': '5',
            'elapsed_ms': '7',
          },
        ],
      });

      expect(call.timestampMs, 1000);
      expect(call.totalDurationMs, 42);
      expect(call.mergedHitCount, 0);
      expect(call.summaryChars, 0);
      expect(call.perEngine.single.hitCount, 5);

      final stat = WebSearchEngineStat.fromJson(<String, Object?>{
        'total_calls': '3',
        'success_calls': double.nan,
        'total_duration_ms': '90',
        'total_hits': '12',
        'last_failure_at': '-1',
        'cooldown_until_ms': '2000',
      });

      expect(stat.totalCalls, 3);
      expect(stat.successCalls, 0);
      expect(stat.totalHits, 12);
      expect(stat.lastFailureAt, isNull);
      expect(stat.cooldownUntilMs, 2000);
    },
  );

  test('web fetch telemetry parses string values and drops invalid counts', () {
    final call = WebFetchCallLog.fromJson(<String, Object?>{
      'timestamp_ms': '1000',
      'url': 'https://example.test',
      'cache_status': 'miss-stored',
      'success': true,
      'total_duration_ms': '30',
      'content_chars': double.infinity,
      'fallback_used': false,
      'winning_engine': AiWebFetchEngineKind.jina.name,
      'per_engine': <Object?>[
        <String, Object?>{
          'kind': AiWebFetchEngineKind.jina.name,
          'success': true,
          'content_bytes': '128',
          'elapsed_ms': '-5',
        },
      ],
    });

    expect(call.timestampMs, 1000);
    expect(call.totalDurationMs, 30);
    expect(call.contentChars, 0);
    expect(call.winningEngine, AiWebFetchEngineKind.jina);
    expect(call.perEngine.single.contentBytes, 128);
    expect(call.perEngine.single.elapsedMs, 0);

    final stat = WebFetchEngineStat.fromJson(<String, Object?>{
      'total_calls': '4',
      'success_calls': '3',
      'total_duration_ms': '120',
      'total_bytes': double.nan,
      'last_invoked_at': '3000',
      'last_quota_at': '-1',
    });

    expect(stat.totalCalls, 4);
    expect(stat.successCalls, 3);
    expect(stat.totalBytes, 0);
    expect(stat.lastInvokedAt, 3000);
    expect(stat.lastQuotaAt, isNull);
  });
}
