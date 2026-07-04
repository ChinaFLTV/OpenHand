import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/net/http_redirect_utils.dart';

void main() {
  group('isRedirectStatusCode', () {
    test('accepts standard redirect status codes only', () {
      expect(isRedirectStatusCode(301), isTrue);
      expect(isRedirectStatusCode(302), isTrue);
      expect(isRedirectStatusCode(303), isTrue);
      expect(isRedirectStatusCode(307), isTrue);
      expect(isRedirectStatusCode(308), isTrue);
      expect(isRedirectStatusCode(300), isFalse);
      expect(isRedirectStatusCode(200), isFalse);
    });
  });

  group('isCrossOriginRedirect', () {
    test('treats scheme and host as case-insensitive origin parts', () {
      expect(
        isCrossOriginRedirect(
          Uri.parse('HTTPS://EXAMPLE.com/path'),
          Uri.parse('https://example.COM/next'),
        ),
        isFalse,
      );
    });

    test('matches explicit default ports with implicit ports', () {
      expect(
        isCrossOriginRedirect(
          Uri.parse('https://example.com:443/path'),
          Uri.parse('https://example.com/next'),
        ),
        isFalse,
      );
    });

    test('detects scheme, host, and non-default port changes', () {
      final source = Uri.parse('https://example.com/path');

      expect(
        isCrossOriginRedirect(source, Uri.parse('http://example.com/path')),
        isTrue,
      );
      expect(
        isCrossOriginRedirect(
          source,
          Uri.parse('https://api.example.com/path'),
        ),
        isTrue,
      );
      expect(
        isCrossOriginRedirect(source, Uri.parse('https://example.com:8443')),
        isTrue,
      );
    });
  });

  test('readResponseHeader performs a case-insensitive trimmed lookup', () {
    expect(
      readResponseHeader(<String, String>{'Location': ' /next '}, 'location'),
      '/next',
    );
    expect(readResponseHeader(<String, String>{}, 'location'), isEmpty);
  });
}
