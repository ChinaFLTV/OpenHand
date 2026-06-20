import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/url_validation.dart';

void main() {
  group('url_validation text extraction', () {
    test('extracts first URL and trims common prose punctuation', () {
      expect(
        firstHttpUrlFromText('目标：`https://linux.do/t/topic/2401043.json`。'),
        'https://linux.do/t/topic/2401043.json',
      );
    });

    test('extracts URLs with escaped forward slashes', () {
      final uris = extractHttpUrisFromText(
        r'''node -e "fetch('https:\/\/linux.do\/t\/topic\/2401043.json')"''',
      );

      expect(uris.map((uri) => uri.toString()), <String>[
        'https://linux.do/t/topic/2401043.json',
      ]);
    });

    test('deduplicates repeated normalized URLs', () {
      final uris = extractHttpUrisFromText(
        'curl https://linux.do/a && curl "https://linux.do/a"',
      );

      expect(uris.map((uri) => uri.toString()), <String>['https://linux.do/a']);
    });

    test('returns null when no valid HTTP URL exists', () {
      expect(firstHttpUrlFromText('no url here'), isNull);
      expect(firstHttpUrlFromText('mailto:dev@example.com'), isNull);
    });
  });
}
