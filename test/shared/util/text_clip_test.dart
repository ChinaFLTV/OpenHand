import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/text_clip.dart';

void main() {
  group('clipText', () {
    test('returns the original text when it fits', () {
      expect(clipText('hello', 5), 'hello');
      expect(clipText('', 0), '');
    });

    test('clips text and appends the configured suffix', () {
      expect(clipText('hello world', 5), 'hello...');
      expect(clipTextWithEllipsis('hello world', 5), 'hello…');
      expect(clipText('hello world', 5, suffix: ''), 'hello');
    });

    test('clips by visible character clusters', () {
      expect(clipTextWithEllipsis('A👍🏽B', 2), 'A👍🏽…');
      expect(clipTextWithEllipsis('éclair', 1), 'é…');
      expect(clipTextWithEllipsis('👨‍👩‍👧‍👦 family', 1), '👨‍👩‍👧‍👦…');
    });

    test('handles non-positive limits consistently', () {
      expect(clipText('hello', 0), '...');
      expect(clipTextWithEllipsis('hello', -2), '…');
    });
  });

  group('clipNullableText', () {
    test('passes null through and clips non-null values', () {
      expect(clipNullableText(null, 4), isNull);
      expect(clipNullableText('abcdef', 4), 'abcd...');
    });
  });
}
