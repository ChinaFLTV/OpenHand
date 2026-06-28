import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/text_search.dart';

void main() {
  group('findTextMatchOffsets', () {
    test('finds case-insensitive offsets by default', () {
      expect(
        findTextMatchOffsets(text: 'Alpha beta ALPHA', query: 'alpha'),
        <int>[0, 11],
      );
    });

    test('can preserve case-sensitive behavior', () {
      expect(
        findTextMatchOffsets(
          text: 'Alpha beta ALPHA',
          query: 'Alpha',
          caseSensitive: true,
        ),
        <int>[0],
      );
    });

    test('supports overlapping and non-overlapping matching', () {
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

    test('bounds result count', () {
      expect(
        findTextMatchOffsets(text: 'aaaa', query: 'a', maxMatches: 2),
        <int>[0, 1],
      );
      expect(
        findTextMatchOffsets(text: 'aaaa', query: 'a', maxMatches: 0),
        isEmpty,
      );
    });
  });
}
