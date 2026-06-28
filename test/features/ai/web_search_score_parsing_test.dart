import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('web search scores accept finite non-negative numeric values only', () {
    expect(webSearchScoreFromValue(0.75), 0.75);
    expect(webSearchScoreFromValue('0.25'), 0.25);
    expect(webSearchScoreFromValue(0), 0);
    expect(webSearchScoreFromValue('-0.1'), isNull);
    expect(webSearchScoreFromValue(double.infinity), isNull);
    expect(webSearchScoreFromValue('NaN'), isNull);
    expect(webSearchScoreFromValue('bad'), isNull);
  });
}
