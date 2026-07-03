import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/web_engine/web_engine_quality.dart';

void main() {
  group('webPromptExcerpt', () {
    test('normalizes whitespace and removes duplicate lines', () {
      expect(
        webPromptExcerpt(' Alpha   beta \nalpha beta\nGamma\tDelta ', 80),
        'Alpha beta\nGamma Delta',
      );
    });

    test('uses compact fallback for inputs without useful lines', () {
      expect(webPromptExcerpt(' a \n b ', 80), 'a b');
    });
  });

  group('webContentQualityScore', () {
    test('scores informative text above empty content', () {
      final score = webContentQualityScore(
        'OpenHand provides a structured desktop workflow with local tools, '
        'session history, source navigation, and reliable AI assisted editing.',
      );

      expect(score, greaterThan(webContentQualityScore('   ')));
    });
  });
}
