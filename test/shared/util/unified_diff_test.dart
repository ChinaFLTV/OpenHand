import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/unified_diff.dart';

void main() {
  group('unifiedDiffLinesFromText', () {
    test('builds a compact unified diff for changed lines', () {
      expect(
        unifiedDiffLinesFromText('one\ntwo\nthree', 'one\n2\nthree'),
        <String>[
          '--- a/file',
          '+++ b/file',
          '@@ -1,3 +1,3 @@',
          ' one',
          '-two',
          '+2',
          ' three',
        ],
      );
    });

    test('returns an empty diff for identical text', () {
      expect(unifiedDiffLinesFromText('same\ntext', 'same\ntext'), isEmpty);
    });
  });

  group('unifiedDiffLineStatsFromText', () {
    test('counts added and removed lines', () {
      final stats = unifiedDiffLineStatsFromText('one\ntwo', 'one\n2\nthree');
      expect(stats.removedLines, 1);
      expect(stats.addedLines, 2);
    });
  });

  group('unifiedDiffLineSummary', () {
    test('uses UTF-8 byte length for max byte limits', () {
      expect(
        unifiedDiffLineSummary(
          '中文',
          '中文!',
          maxBytes: 5,
          beforeSha: '1234567890abcdef',
          afterSha: 'fedcba0987654321',
        ),
        '<file too large for inline diff; '
        'before=6B sha=1234567890ab, after=7B sha=fedcba098765>',
      );
    });

    test('can disable compact mini diff with a non-positive threshold', () {
      expect(
        unifiedDiffLineSummary(
          'same\nold\nsame',
          'same\nnew\nsame',
          miniDiffMaxBytes: 0,
        ),
        ' same\n-old\n+new\n same',
      );
    });

    test('keeps only changed lines for compact mini diff', () {
      expect(
        unifiedDiffLineSummary(
          'same\nold\nsame',
          'same\nnew\nsame',
          miniDiffMaxBytes: 1,
        ),
        '-old\n+new',
      );
    });
  });
}
