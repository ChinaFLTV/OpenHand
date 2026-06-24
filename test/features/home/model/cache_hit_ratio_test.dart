import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/model/cache_hit_ratio.dart';

void main() {
  group('cache hit ratio math', () {
    test('OpenAI-compatible cached tokens are part of prompt tokens', () {
      expect(
        computeUncachedPromptTokens(
          promptTokens: 17212,
          cacheReadTokens: 16000,
          claudeStyle: false,
        ),
        1212,
      );
      expect(
        computeCacheHitRatio(
          promptTokens: 17212,
          cacheReadTokens: 16000,
          claudeStyle: false,
        ),
        closeTo(0.9296, 0.0001),
      );
      expect(
        computeCacheHitDenominatorTokens(
          promptTokens: 17212,
          cacheReadTokens: 16000,
          claudeStyle: false,
        ),
        17212,
      );
    });

    test('Claude cache read tokens are separate from input tokens', () {
      expect(
        computeUncachedPromptTokens(
          promptTokens: 1212,
          cacheReadTokens: 16000,
          claudeStyle: true,
        ),
        1212,
      );
      expect(
        computeCacheHitRatio(
          promptTokens: 1212,
          cacheReadTokens: 16000,
          claudeStyle: true,
        ),
        closeTo(0.9296, 0.0001),
      );
      expect(
        computeCacheHitDenominatorTokens(
          promptTokens: 1212,
          cacheReadTokens: 16000,
          claudeStyle: true,
        ),
        17212,
      );
    });

    test(
      'falls back to cache reads when compatible prompt total is absent',
      () {
        expect(
          computeCacheHitRatio(
            promptTokens: 0,
            cacheReadTokens: 2048,
            claudeStyle: false,
          ),
          1.0,
        );
      },
    );
  });
}
