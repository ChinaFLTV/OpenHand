import 'dart:convert';
import 'dart:typed_data';

class BoundedBase64FormatException implements Exception {
  const BoundedBase64FormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BoundedBase64SizeException implements Exception {
  const BoundedBase64SizeException({
    required this.decodedBytes,
    required this.maxDecodedBytes,
  });

  final int decodedBytes;
  final int maxDecodedBytes;

  @override
  String toString() => 'Decoded Base64 payload exceeds $maxDecodedBytes bytes.';
}

/// Validates the encoded shape and decoded size before allocating the decoded
/// byte buffer. Only canonical standard Base64 is accepted.
Uint8List decodeBase64Bounded(String encoded, {required int maxDecodedBytes}) {
  if (maxDecodedBytes < 0) {
    throw ArgumentError.value(
      maxDecodedBytes,
      'maxDecodedBytes',
      'Must not be negative.',
    );
  }
  if (encoded.isEmpty || encoded.length % 4 != 0) {
    throw const BoundedBase64FormatException('Invalid Base64 payload.');
  }

  var padding = 0;
  if (encoded.codeUnitAt(encoded.length - 1) == _equalsCodeUnit) {
    padding += 1;
    if (encoded.length > 1 &&
        encoded.codeUnitAt(encoded.length - 2) == _equalsCodeUnit) {
      padding += 1;
    }
  }
  final contentLength = encoded.length - padding;
  for (var index = 0; index < encoded.length; index++) {
    final codeUnit = encoded.codeUnitAt(index);
    if (index >= contentLength) {
      if (codeUnit != _equalsCodeUnit) {
        throw const BoundedBase64FormatException('Invalid Base64 padding.');
      }
      continue;
    }
    if (!_isBase64CodeUnit(codeUnit)) {
      throw const BoundedBase64FormatException('Invalid Base64 payload.');
    }
  }

  final decodedBytes = encoded.length ~/ 4 * 3 - padding;
  if (decodedBytes > maxDecodedBytes) {
    throw BoundedBase64SizeException(
      decodedBytes: decodedBytes,
      maxDecodedBytes: maxDecodedBytes,
    );
  }
  try {
    return base64Decode(encoded);
  } on FormatException {
    throw const BoundedBase64FormatException('Invalid Base64 payload.');
  }
}

const int _equalsCodeUnit = 0x3d;

bool _isBase64CodeUnit(int value) {
  return (value >= 0x41 && value <= 0x5a) ||
      (value >= 0x61 && value <= 0x7a) ||
      (value >= 0x30 && value <= 0x39) ||
      value == 0x2b ||
      value == 0x2f;
}
