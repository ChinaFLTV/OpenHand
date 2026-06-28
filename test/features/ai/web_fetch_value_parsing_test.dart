import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('web fetch scores accept finite non-negative numeric values only', () {
    expect(webFetchScoreFromValue(0.75), 0.75);
    expect(webFetchScoreFromValue('0.25'), 0.25);
    expect(webFetchScoreFromValue(0), 0);
    expect(webFetchScoreFromValue('-0.1'), isNull);
    expect(webFetchScoreFromValue(double.infinity), isNull);
    expect(webFetchScoreFromValue(double.nan), isNull);
    expect(webFetchScoreFromValue('NaN'), isNull);
    expect(webFetchScoreFromValue('bad'), isNull);
  });

  test('web fetch http statuses accept valid integral status values only', () {
    expect(webFetchHttpStatusFromValue(100), 100);
    expect(webFetchHttpStatusFromValue(200), 200);
    expect(webFetchHttpStatusFromValue('200'), 200);
    expect(webFetchHttpStatusFromValue('200.0'), 200);
    expect(webFetchHttpStatusFromValue(599), 599);
    expect(webFetchHttpStatusFromValue(99), isNull);
    expect(webFetchHttpStatusFromValue(600), isNull);
    expect(webFetchHttpStatusFromValue(200.5), isNull);
    expect(webFetchHttpStatusFromValue(-1), isNull);
    expect(webFetchHttpStatusFromValue(double.infinity), isNull);
    expect(webFetchHttpStatusFromValue(double.nan), isNull);
    expect(webFetchHttpStatusFromValue('bad'), isNull);
  });

  test('web fetch content normalizes unsafe status and score values', () {
    final invalidContent = WebFetchEngineContent(
      url: 'https://example.com',
      title: 'Example',
      content: 'body',
      statusCode: 600,
      score: double.infinity,
    );
    expect(invalidContent.statusCode, isNull);
    expect(invalidContent.score, isNull);

    final validContent = WebFetchEngineContent(
      url: 'https://example.com',
      title: 'Example',
      content: 'body',
      statusCode: 204,
      score: 1.25,
    );
    expect(validContent.statusCode, 204);
    expect(validContent.score, 1.25);
  });
}
