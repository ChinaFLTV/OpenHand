import 'dart:convert';
import 'dart:typed_data';

import 'argument_guards.dart';
import 'byte_size_format.dart';
import 'text_normalization.dart';

const int _maxIgnoredBase64WhitespaceCharacters = 64 * kBytesPerKiB;

/// 有界 Base64 解码的可识别异常基类。
sealed class BoundedBase64Exception implements Exception {
  const BoundedBase64Exception();
}

class BoundedBase64FormatException extends BoundedBase64Exception {
  const BoundedBase64FormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BoundedBase64SizeException extends BoundedBase64Exception {
  const BoundedBase64SizeException({
    required this.decodedBytes,
    required this.maxDecodedBytes,
  });

  final int decodedBytes;
  final int maxDecodedBytes;

  @override
  String toString() => 'Base64 解码结果超过 $maxDecodedBytes 字节。';
}

/// 分配解码缓冲前校验编码格式与结果大小，仅接受规范的标准 Base64。
Uint8List decodeBase64Bounded(String encoded, {required int maxDecodedBytes}) {
  requireNonNegativeInt(maxDecodedBytes, 'maxDecodedBytes');
  if (encoded.isEmpty || encoded.length % 4 != 0) {
    throw const BoundedBase64FormatException('Base64 内容格式无效。');
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
  final decodedBytes = encoded.length ~/ 4 * 3 - padding;
  if (decodedBytes > maxDecodedBytes) {
    throw BoundedBase64SizeException(
      decodedBytes: decodedBytes,
      maxDecodedBytes: maxDecodedBytes,
    );
  }
  for (var index = 0; index < encoded.length; index++) {
    final codeUnit = encoded.codeUnitAt(index);
    if (index >= contentLength) {
      if (codeUnit != _equalsCodeUnit) {
        throw const BoundedBase64FormatException('Base64 填充格式无效。');
      }
      continue;
    }
    if (!_isBase64CodeUnit(codeUnit)) {
      throw const BoundedBase64FormatException('Base64 内容格式无效。');
    }
  }

  try {
    return base64Decode(encoded);
  } on FormatException {
    throw const BoundedBase64FormatException('Base64 内容格式无效。');
  }
}

/// 解码允许空白、Base64URL 字符和缺失尾部填充的文本，同时限制输入与输出大小。
Uint8List decodeFlexibleBase64Bounded(
  String encoded, {
  required int maxDecodedBytes,
}) {
  requireNonNegativeInt(maxDecodedBytes, 'maxDecodedBytes');
  final maxEncodedCharacters = ((maxDecodedBytes + 2) ~/ 3) * 4;
  if (encoded.length >
      maxEncodedCharacters + _maxIgnoredBase64WhitespaceCharacters) {
    throw BoundedBase64SizeException(
      decodedBytes: encoded.length ~/ 4 * 3,
      maxDecodedBytes: maxDecodedBytes,
    );
  }
  final compact = encoded.replaceAll(kInlineWhitespacePattern, '');
  try {
    return decodeBase64Bounded(
      base64.normalize(compact),
      maxDecodedBytes: maxDecodedBytes,
    );
  } on FormatException {
    throw const BoundedBase64FormatException('Base64 内容格式无效。');
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
