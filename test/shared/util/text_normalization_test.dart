import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/text_normalization.dart';

void main() {
  group('normalizeAsciiLookupKey', () {
    test('removes non ASCII alphanumeric separators', () {
      expect(
        normalizeAsciiLookupKey(' Agent_Task Progress! '),
        'agenttaskprogress',
      );
      expect(normalizeAsciiLookupKey('中文 Agent-01'), 'agent01');
    });
  });

  group('normalizeAsciiSlugKey', () {
    test('replaces separator runs with hyphens', () {
      expect(normalizeAsciiSlugKey(' Foo_bar.Baz '), 'foo-bar-baz');
      expect(normalizeAsciiSlugKey('__foo__'), '-foo-');
    });
  });

  group('normalizeSnakeStorageKey', () {
    test('replaces whitespace and hyphen runs with underscores', () {
      expect(
        normalizeSnakeStorageKey(' Worker Removal-Policy '),
        'worker_removal_policy',
      );
      expect(normalizeSnakeStorageKey('already_ok.value'), 'already_ok.value');
    });
  });
}
