import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/text_fingerprint.dart';

void main() {
  group('boundedTextFingerprint', () {
    test('keeps equal text fingerprints equal', () {
      expect(
        boundedTextFingerprint('OpenHand'),
        boundedTextFingerprint('OpenHand'),
      );
    });

    test('samples long text by edges and middle', () {
      final base = '${'a' * 20}middle${'z' * 20}';
      final changedMiddle = '${'a' * 20}center${'z' * 20}';
      final changedEdge = 'b${'a' * 19}middle${'z' * 20}';

      expect(
        boundedTextFingerprint(base, edgeLength: 4),
        isNot(boundedTextFingerprint(changedMiddle, edgeLength: 4)),
      );
      expect(
        boundedTextFingerprint(base, edgeLength: 4),
        isNot(boundedTextFingerprint(changedEdge, edgeLength: 4)),
      );
    });
  });

  group('compactTextSignature', () {
    test('uses the configured empty signature for null and empty text', () {
      expect(compactTextSignature(null), '0');
      expect(compactTextSignature('', emptySignature: 'empty'), 'empty');
    });

    test('does not duplicate overlapping head and tail text', () {
      expect(
        compactTextSignature('abcdef', headLength: 4, tailLength: 4),
        '6:abcd:ef',
      );
      expect(compactTextSignature('abc'), '3:abc:');
    });

    test('keeps non-overlapping head and tail samples for long text', () {
      expect(
        compactTextSignature(
          'abcdefghijklmnopqrstuvwxyz',
          headLength: 4,
          tailLength: 3,
        ),
        '26:abcd:xyz',
      );
    });

    test('normalizes negative sample lengths to zero', () {
      expect(
        compactTextSignature('abcdef', headLength: -1, tailLength: -1),
        '6::',
      );
    });

    test('stringifies non-string values safely', () {
      expect(
        compactTextSignature(
          <String, Object?>{'b': 2},
          headLength: 20,
          tailLength: 0,
        ),
        '7:{"b":2}:',
      );
    });
  });

  group('scaledNumberSeriesFingerprint', () {
    test('is stable for the same finite values and scale', () {
      expect(
        scaledNumberSeriesFingerprint(<num>[1, 2.5, -3], scale: 100),
        scaledNumberSeriesFingerprint(<num>[1, 2.5, -3], scale: 100),
      );
    });

    test('normalizes zero and negative scale values', () {
      expect(
        scaledNumberSeriesFingerprint(<num>[1.2], scale: 0),
        scaledNumberSeriesFingerprint(<num>[1.2], scale: 1),
      );
      expect(
        scaledNumberSeriesFingerprint(<num>[1.2], scale: -10),
        scaledNumberSeriesFingerprint(<num>[1.2], scale: 10),
      );
    });

    test('treats non-finite values as zero contributors', () {
      expect(
        scaledNumberSeriesFingerprint(<num>[double.nan, double.infinity]),
        scaledNumberSeriesFingerprint(<num>[0, 0]),
      );
    });
  });
}
