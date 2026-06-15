import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/unified_diff.dart';

void main() {
  group('unifiedDiffLinesFromText', () {
    test('returns empty output for identical content', () {
      expect(unifiedDiffLinesFromText('a\nb', 'a\nb'), isEmpty);
    });

    test('handles newly created files without phantom empty deletion', () {
      expect(unifiedDiffLinesFromText('', 'a\nb'), <String>[
        '--- /dev/null',
        '+++ b/file',
        '@@ -0,0 +1,2 @@',
        '+a',
        '+b',
      ]);
    });

    test('emits unified hunk headers and changed lines', () {
      expect(
        unifiedDiffLinesFromText('a\nb\nc', 'a\nB\nc', contextLines: 1),
        <String>[
          '--- a/file',
          '+++ b/file',
          '@@ -1,3 +1,3 @@',
          ' a',
          '-b',
          '+B',
          ' c',
        ],
      );
    });
  });

  group('unifiedDiffLineSummary', () {
    test('uses compact mode above mini diff limit', () {
      expect(
        unifiedDiffLineSummary('same\nold', 'same\nnew', miniDiffMaxBytes: 4),
        '-old\n+new',
      );
    });

    test('uses bounded placeholder above max byte limit', () {
      expect(
        unifiedDiffLineSummary(
          'abcdef',
          'abcxyz',
          maxBytes: 4,
          beforeSha: '1234567890abcdef',
          afterSha: 'fedcba0987654321',
        ),
        '<file too large for inline diff; before=6B sha=1234567890ab, after=6B sha=fedcba098765>',
      );
    });
  });
}
