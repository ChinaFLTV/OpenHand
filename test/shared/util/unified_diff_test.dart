import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/unified_diff.dart';

void main() {
  group('unifiedDiffLineStats', () {
    test(
      'large fallback excludes unchanged lines between distant replacements',
      () {
        final (before, after) = _distantReplacementFixture();

        final stats = unifiedDiffLineStats(before, after, maxMyersLineTotal: 1);
        final diffStats = _lineStatsFromUnifiedDiff(
          unifiedDiffLines(before, after, maxMyersLineTotal: 1),
        );

        expect(stats.addedLines, 2);
        expect(stats.removedLines, 2);
        expect(diffStats.addedLines, 2);
        expect(diffStats.removedLines, 2);
      },
    );

    test(
      'large fallback handles a single insertion without shifting the tail',
      () {
        final before = <String>[
          for (var i = 0; i < 900; i++) 'prefix $i',
          for (var i = 0; i < 900; i++) 'suffix $i',
        ];
        final after = <String>[
          for (var i = 0; i < 900; i++) 'prefix $i',
          'inserted line',
          for (var i = 0; i < 900; i++) 'suffix $i',
        ];

        final stats = unifiedDiffLineStats(before, after, maxMyersLineTotal: 1);

        expect(stats.addedLines, 1);
        expect(stats.removedLines, 0);
      },
    );
  });
}

(List<String>, List<String>) _distantReplacementFixture() {
  return (
    <String>[
      for (var i = 0; i < 614; i++) 'prefix $i',
      r'''if echo "$all" | grep -qE 'op-buffer-[0-9]+-[0-9]+-[0-9]+-[0-9]+\.'; then''',
      for (var i = 0; i < 12; i++) 'unchanged middle $i',
      r'''if echo "$cmdb_hostname_all" | grep -qE 'op-buffer-[0-9]+-[0-9]+\.'; then''',
      for (var i = 0; i < 500; i++) 'suffix $i',
    ],
    <String>[
      for (var i = 0; i < 614; i++) 'prefix $i',
      r'''if echo "$all" | grep -qE 'inf-buffer-[0-9]+-[0-9]+-[0-9]+-[0-9]+\.'; then''',
      for (var i = 0; i < 12; i++) 'unchanged middle $i',
      r'''if echo "$cmdb_hostname_all" | grep -qE 'inf-buffer-[0-9]+-[0-9]+\.'; then''',
      for (var i = 0; i < 500; i++) 'suffix $i',
    ],
  );
}

({int addedLines, int removedLines}) _lineStatsFromUnifiedDiff(
  Iterable<String> lines,
) {
  var added = 0;
  var removed = 0;
  for (final line in lines) {
    if (line.startsWith('+++') || line.startsWith('---')) continue;
    if (line.startsWith('+')) added += 1;
    if (line.startsWith('-')) removed += 1;
  }
  return (addedLines: added, removedLines: removed);
}
