import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/text_search.dart';

void main() {
  group('findTextMatchOffsets', () {
    test('finds case-insensitive matches by default', () {
      expect(
        findTextMatchOffsets(text: 'Alpha alpha ALPHA', query: 'alpha'),
        <int>[0, 6, 12],
      );
    });

    test('can require case-sensitive matches', () {
      expect(
        findTextMatchOffsets(
          text: 'Alpha alpha ALPHA',
          query: 'Alpha',
          caseSensitive: true,
        ),
        <int>[0],
      );
    });

    test('supports overlapping and non-overlapping searches', () {
      expect(findTextMatchOffsets(text: 'aaaa', query: 'aa'), <int>[0, 1, 2]);
      expect(
        findTextMatchOffsets(
          text: 'aaaa',
          query: 'aa',
          allowOverlapping: false,
        ),
        <int>[0, 2],
      );
    });

    test('respects maxMatches and invalid inputs', () {
      expect(
        findTextMatchOffsets(text: 'aaaa', query: 'a', maxMatches: 2),
        <int>[0, 1],
      );
      expect(
        findTextMatchOffsets(text: 'aaaa', query: 'a', maxMatches: 0),
        isEmpty,
      );
      expect(findTextMatchOffsets(text: '', query: 'a'), isEmpty);
      expect(findTextMatchOffsets(text: 'aaaa', query: ''), isEmpty);
    });

    test(
      'keeps offsets in original text coordinates when lowercase expands',
      () {
        expect(findTextMatchOffsets(text: 'İabc', query: 'a'), <int>[1]);
        expect(findTextMatchOffsets(text: 'aİbc', query: 'bc'), <int>[2]);
      },
    );

    test('matches expanded lowercase characters by original offsets', () {
      expect(findTextMatchOffsets(text: 'İabc', query: 'i'), <int>[0]);
      expect(findTextMatchOffsets(text: 'İİ', query: 'i'), <int>[0, 1]);
      expect(findTextMatchOffsets(text: 'İİ', query: 'İ'), <int>[0, 1]);
    });

    test('uses one folded text source for expanded lowercase searches', () {
      expect(findTextMatchOffsets(text: 'İΟΣ', query: 'Σ'), <int>[2]);
    });

    test('keeps non-overlapping searches finite after lowercase expansion', () {
      expect(
        findTextMatchOffsets(text: 'İİİ', query: 'İ', allowOverlapping: false),
        <int>[0, 1, 2],
      );
    });
  });
}
