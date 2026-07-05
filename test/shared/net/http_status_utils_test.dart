import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/net/http_status_utils.dart';

void main() {
  group('isHttpSuccessStatus', () {
    test('accepts the full 2xx range', () {
      expect(isHttpSuccessStatus(200), isTrue);
      expect(isHttpSuccessStatus(204), isTrue);
      expect(isHttpSuccessStatus(299), isTrue);
    });

    test('rejects statuses outside the 2xx range', () {
      expect(isHttpSuccessStatus(199), isFalse);
      expect(isHttpSuccessStatus(300), isFalse);
      expect(isHttpSuccessStatus(500), isFalse);
    });
  });

  group('isHttpFailureStatus', () {
    test('is the inverse of isHttpSuccessStatus', () {
      expect(isHttpFailureStatus(200), isFalse);
      expect(isHttpFailureStatus(404), isTrue);
    });
  });
}
