import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/model/cache_hit_ratio.dart';

void main() {
  group('computeCacheHitDenominatorTokens', () {
    test('uses Claude-style prompt plus cache read denominator', () {
      expect(
        computeCacheHitDenominatorTokens(
          promptTokens: 120,
          cacheReadTokens: 30,
          claudeStyle: true,
        ),
        150,
      );
    });

    test('ignores negative token counts gracefully', () {
      expect(
        computeCacheHitDenominatorTokens(
          promptTokens: -20,
          cacheReadTokens: 30,
          claudeStyle: true,
        ),
        30,
      );
      expect(
        computeCacheHitDenominatorTokens(
          promptTokens: -20,
          cacheReadTokens: -30,
          claudeStyle: false,
        ),
        0,
      );
    });
  });

  group('computeUncachedPromptTokens', () {
    test('returns non-negative uncached prompt tokens', () {
      expect(
        computeUncachedPromptTokens(
          promptTokens: 100,
          cacheReadTokens: 35,
          claudeStyle: false,
        ),
        65,
      );
      expect(
        computeUncachedPromptTokens(
          promptTokens: 40,
          cacheReadTokens: 80,
          claudeStyle: false,
        ),
        0,
      );
    });

    test('normalizes invalid token counts before subtracting', () {
      expect(
        computeUncachedPromptTokens(
          promptTokens: -10,
          cacheReadTokens: 5,
          claudeStyle: false,
        ),
        0,
      );
      expect(
        computeUncachedPromptTokens(
          promptTokens: 10,
          cacheReadTokens: -5,
          claudeStyle: false,
        ),
        10,
      );
    });
  });

  group('computeCacheHitRatio', () {
    test('returns a safe unit interval ratio', () {
      expect(
        computeCacheHitRatio(
          promptTokens: 80,
          cacheReadTokens: 20,
          claudeStyle: false,
        ),
        0.25,
      );
      expect(
        computeCacheHitRatio(
          promptTokens: 10,
          cacheReadTokens: 50,
          claudeStyle: false,
        ),
        1,
      );
      expect(
        computeCacheHitRatio(
          promptTokens: 0,
          cacheReadTokens: 0,
          claudeStyle: false,
        ),
        0,
      );
    });
  });
}
