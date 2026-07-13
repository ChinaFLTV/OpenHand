import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/bounded_base64.dart';

void main() {
  test('decodes canonical base64 within the byte limit', () {
    final encoded = base64Encode(utf8.encode('hello'));

    expect(
      utf8.decode(decodeBase64Bounded(encoded, maxDecodedBytes: 5)),
      'hello',
    );
  });

  test('rejects decoded data above the byte limit before decoding', () {
    final encoded = base64Encode(List<int>.filled(6, 1));

    expect(
      () => decodeBase64Bounded(encoded, maxDecodedBytes: 5),
      throwsA(isA<BoundedBase64SizeException>()),
    );
  });

  test('rejects malformed alphabet and padding', () {
    expect(
      () => decodeBase64Bounded('abc*', maxDecodedBytes: 8),
      throwsA(isA<BoundedBase64FormatException>()),
    );
    expect(
      () => decodeBase64Bounded('ab=c', maxDecodedBytes: 8),
      throwsA(isA<BoundedBase64FormatException>()),
    );
  });
}
