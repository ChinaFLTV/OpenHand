import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/web_engine/web_engine_quality.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_engine.dart';
import 'package:openhand/features/ai/service/web_search/web_search_engine.dart';

void main() {
  group('webEngineScoreFromValue', () {
    test('keeps non-negative scores and rejects invalid scores', () {
      expect(webEngineScoreFromValue('0.75'), 0.75);
      expect(webEngineScoreFromValue(2), 2);
      expect(webEngineScoreFromValue(0), 0);
      expect(webEngineScoreFromValue(-0.1), isNull);
      expect(webEngineScoreFromValue('bad'), isNull);
    });

    test('backs web search and fetch score parsing', () {
      expect(webSearchScoreFromValue('0.5'), 0.5);
      expect(webFetchScoreFromValue('0.5'), 0.5);
      expect(webSearchScoreFromValue(-1), isNull);
      expect(webFetchScoreFromValue(-1), isNull);
    });
  });
}
