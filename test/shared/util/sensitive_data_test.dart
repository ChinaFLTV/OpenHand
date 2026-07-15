import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/sensitive_data.dart';

void main() {
  test('sensitive key detection normalizes common separators', () {
    for (final key in <String>[
      'authorization',
      'x-api-key',
      'api_key',
      'accessToken',
      'refresh-token',
      'client_secret',
      'proxy authorization',
      'request_signature',
    ]) {
      expect(isSensitiveDataKey(key), isTrue, reason: key);
    }
    expect(isSensitiveDataKey('token_estimate'), isTrue);
    expect(isSensitiveDataKey('device_id'), isFalse);
    expect(isSensitiveDataKey('max_points'), isFalse);
  });

  test('query sanitization redacts secrets and bounds retained data', () {
    final sanitized = redactSensitiveStringMap(
      <String, String>{
        'token': 'top-secret',
        'api_key': 'another-secret',
        'q': 'abcdefgh',
        'ignored': 'value',
      },
      maxEntries: 3,
      maxValueCharacters: 4,
    );

    expect(sanitized, <String, String>{
      'token': kOpenHandRedactedValue,
      'api_key': kOpenHandRedactedValue,
      'q': 'abcd',
    });
  });

  test('URI logging removes credentials from query strings', () {
    final sanitized = redactSensitiveUriForLogging(
      'https://user:password@localhost/events?token=secret&device_id=desktop',
    );

    expect(sanitized, isNot(contains('secret')));
    expect(sanitized, isNot(contains('password')));
    expect(
      sanitized,
      contains(Uri.encodeQueryComponent(kOpenHandRedactedValue)),
    );
    expect(sanitized, contains('device_id=desktop'));
  });
}
