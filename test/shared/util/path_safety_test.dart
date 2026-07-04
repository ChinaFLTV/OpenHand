import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/path_safety.dart';
import 'package:path/path.dart' as p;

void main() {
  group('isPathWithinOrEqual', () {
    test('accepts the same path and descendants after normalization', () {
      final parent = p.join(p.current, 'project');
      final descendant = p.join(parent, 'lib', '..', 'test');

      expect(isPathWithinOrEqual(parent, parent), isTrue);
      expect(isPathWithinOrEqual(parent, descendant), isTrue);
    });

    test('rejects sibling paths', () {
      final parent = p.join(p.current, 'project');

      expect(isPathWithinOrEqual(parent, '$parent-other'), isFalse);
      expect(
        isPathWithinOrEqual(parent, p.join(p.dirname(parent), 'other')),
        isFalse,
      );
    });
  });

  group('safeRelativePathError', () {
    test('accepts normalized relative paths', () {
      expect(safeRelativePathError('notes/today.md'), isNull);
      expect(safeRelativePathError(' notes/./today.md '), isNull);
    });

    test('rejects empty, rooted, and url paths', () {
      expect(safeRelativePathError('  '), isNotNull);
      expect(safeRelativePathError(p.absolute('file.txt')), isNotNull);
      expect(safeRelativePathError('https://example.com/file.txt'), isNotNull);
    });

    test('rejects parent traversal across supported path styles', () {
      expect(safeRelativePathError('../secret.txt'), isNotNull);
      expect(safeRelativePathError(r'..\secret.txt'), isNotNull);
      expect(safeRelativePathError('safe/../secret.txt'), isNotNull);
    });

    test('rejects Windows rooted and drive-relative paths on any host', () {
      expect(safeRelativePathError(r'C:\temp\file.txt'), isNotNull);
      expect(safeRelativePathError(r'C:temp\file.txt'), isNotNull);
      expect(safeRelativePathError(r'\\server\share\file.txt'), isNotNull);
    });

    test('rejects null bytes before filesystem access', () {
      expect(safeRelativePathError('safe\u0000name.txt'), isNotNull);
    });
  });

  group('safeRelativePathForDisplay', () {
    test('uses a relative display path only for descendants', () {
      final base = p.join(p.current, 'project');
      final child = p.join(base, 'lib', 'main.dart');
      final outside = p.join(p.dirname(base), 'other', 'main.dart');

      expect(
        safeRelativePathForDisplay(child, from: base),
        p.join('lib', 'main.dart'),
      );
      expect(
        safeRelativePathForDisplay(outside, from: base),
        p.normalize(outside),
      );
    });
  });

  group('ancestorDirectoriesFrom', () {
    test('returns the start directory before parents by default', () {
      final start = p.join(p.current, 'tmp', 'project', 'lib');
      final project = p.dirname(start);
      final tmp = p.dirname(project);

      expect(ancestorDirectoriesFrom(start, maxDepth: 3), <String>[
        start,
        project,
        tmp,
      ]);
    });

    test('can return root first and clamps invalid depth', () {
      final start = p.join(p.current, 'tmp', 'project', 'lib');
      final project = p.dirname(start);
      final tmp = p.dirname(project);

      expect(
        ancestorDirectoriesFrom(start, rootFirst: true, maxDepth: 3),
        <String>[tmp, project, start],
      );
      expect(ancestorDirectoriesFrom(start, maxDepth: 0), isEmpty);
    });
  });
}
