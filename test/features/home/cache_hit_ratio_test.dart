import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/model/cache_hit_ratio.dart';

void main() {
  test('uses claude-style denominator when prompt excludes cache-read tokens', () {
    final ratio = computeCacheHitRatio(
      promptTokens: 80,
      cacheReadTokens: 20,
      claudeStyle: true,
    );
    expect(ratio, closeTo(0.2, 0.0001));
  });

  test('uses openai-style denominator when prompt already includes cache-read tokens', () {
    final ratio = computeCacheHitRatio(
      promptTokens: 100,
      cacheReadTokens: 20,
      claudeStyle: false,
    );
    expect(ratio, closeTo(0.2, 0.0001));
  });

  test('returns zero when denominator is not positive', () {
    expect(
      computeCacheHitRatio(
        promptTokens: 0,
        cacheReadTokens: 0,
        claudeStyle: true,
      ),
      0,
    );
    expect(
      computeCacheHitRatio(
        promptTokens: 0,
        cacheReadTokens: 10,
        claudeStyle: false,
      ),
      0,
    );
    expect(
      computeCacheHitRatio(
        promptTokens: 10,
        cacheReadTokens: 10,
        claudeStyle: false,
      ),
      1,
    );
  });

  test('computes uncached prompt tokens per protocol family', () {
    expect(
      computeUncachedPromptTokens(
        promptTokens: 80,
        cacheReadTokens: 20,
        claudeStyle: true,
      ),
      80,
    );
    expect(
      computeUncachedPromptTokens(
        promptTokens: 100,
        cacheReadTokens: 20,
        claudeStyle: false,
      ),
      80,
    );
  });
}
