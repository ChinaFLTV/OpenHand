import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/version_compare.dart';

void main() {
  group('versionPartsFromText', () {
    test('extracts normalized semantic version parts', () {
      expect(versionPartsFromText(' v1.2.3-beta+build '), <int>[1, 2, 3]);
      expect(versionPartsFromText('node 20.11.1'), <int>[20, 11, 1]);
    });

    test('uses an empty list when no version token exists', () {
      expect(versionPartsFromText('latest'), isEmpty);
    });
  });

  group('isStrictSemanticVersionText', () {
    test('accepts only three numeric dot segments', () {
      expect(isStrictSemanticVersionText('1.2.3'), isTrue);
      expect(isStrictSemanticVersionText('v1.2.3'), isFalse);
      expect(isStrictSemanticVersionText('1.2'), isFalse);
    });
  });

  group('compareSemanticVersions', () {
    test('compares numeric version segments', () {
      expect(compareSemanticVersions('1.10.0', '1.2.9'), isPositive);
      expect(compareSemanticVersions('2.0', '2.0.0'), 0);
      expect(compareSemanticVersions('1.0.1', '1.0.2'), isNegative);
    });

    test('can compare missing version parts without lexical fallback', () {
      expect(
        compareSemanticVersions('latest', '1.0.0', lexicalFallback: false),
        isNegative,
      );
    });
  });
}
