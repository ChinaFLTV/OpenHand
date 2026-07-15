import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/net/http_redirect_utils.dart';

void main() {
  test('same-origin validation compares scheme, host, and effective port', () {
    final request = Uri.parse('http://127.0.0.1:8080/api/sessions');

    expect(isSameHttpOrigin(request, 'http://127.0.0.1:8080'), isTrue);
    expect(isSameHttpOrigin(request, 'http://127.0.0.1:8080/'), isTrue);
    expect(isSameHttpOrigin(request, 'http://localhost:8080'), isFalse);
    expect(isSameHttpOrigin(request, 'https://127.0.0.1:8080'), isFalse);
    expect(isSameHttpOrigin(request, 'http://127.0.0.1:8081'), isFalse);
  });

  test('origin validation rejects malformed or credential-bearing values', () {
    final request = Uri.parse('https://openhand.local/api/health');

    expect(isSameHttpOrigin(request, null), isFalse);
    expect(isSameHttpOrigin(request, 'null'), isFalse);
    expect(
      isSameHttpOrigin(request, 'https://user:pass@openhand.local'),
      isFalse,
    );
    expect(
      isSameHttpOrigin(request, 'https://openhand.local?token=secret'),
      isFalse,
    );
  });
}
