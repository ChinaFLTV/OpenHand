import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/text_clip.dart';
import 'package:openhand/shared/util/text_fingerprint.dart';

void main() {
  group('clipText', () {
    test('keeps short values unchanged', () {
      expect(clipText('abc', 3), 'abc');
      expect(clipNullableText(null, 3), isNull);
    });

    test('clips long values and guards invalid limits', () {
      expect(clipText('abcdef', 3), 'abc...');
      expect(clipText('abcdef', 0), '...');
      expect(clipText('abcdef', -1), '...');
      expect(clipNullableText('abcdef', 2, suffix: '…'), 'ab…');
    });
  });

  group('compactTextSignature', () {
    test('matches length head tail format', () {
      expect(compactTextSignature(''), '0');
      expect(compactTextSignature('', emptySignature: '0::'), '0::');
      expect(
        compactTextSignature('abcdefghijklmnopqrstuvwxyz'),
        '26:abcdefghijklmnopqrstuvwxyz:cdefghijklmnopqrstuvwxyz',
      );
      expect(
        compactTextSignature(
          'abcdefghijklmnopqrstuvwxyz',
          headLength: 4,
          tailLength: 3,
        ),
        '26:abcd:xyz',
      );
    });
  });

  group('boundedTextFingerprint', () {
    test('handles edge length defensively', () {
      expect(boundedTextFingerprint('abcdef', edgeLength: 0), isA<int>());
      expect(boundedTextFingerprint('abcdef', edgeLength: -10), isA<int>());
      expect(
        boundedTextFingerprint('abcdef', edgeLength: 2),
        boundedTextFingerprint('abcdef', edgeLength: 2),
      );
    });
  });
}
