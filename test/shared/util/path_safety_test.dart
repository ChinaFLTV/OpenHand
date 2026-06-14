import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/path_safety.dart';
import 'package:path/path.dart' as p;

void main() {
  group('path safety helpers', () {
    test('detect path containment after normalization', () {
      final root = p.normalize('/tmp/openhand/root');

      expect(isPathWithinOrEqual(root, p.join(root, 'child.txt')), isTrue);
      expect(isPathWithinOrEqual(root, root), isTrue);
      expect(
        isPathWithinOrEqual(root, '/tmp/openhand/root2/file.txt'),
        isFalse,
      );
    });

    test('rejects parent traversal before normalize can hide it', () {
      expect(safeRelativePathError('references/readme.md'), isNull);
      expect(
        safeRelativePathError('references/../outside.md'),
        contains('parent directories'),
      );
      expect(safeRelativePathError(''), contains('empty'));
      expect(safeRelativePathError('/tmp/file'), contains('relative'));
    });

    test('uses absolute fallback for unsafe display paths', () {
      final root = p.normalize('/tmp/openhand/root');
      expect(
        safeRelativePathForDisplay(p.join(root, 'a.txt'), from: root),
        'a.txt',
      );
      expect(
        safeRelativePathForDisplay('/tmp/openhand/root2/a.txt', from: root),
        p.normalize('/tmp/openhand/root2/a.txt'),
      );
    });
  });
}
