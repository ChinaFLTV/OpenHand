import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

String stableFnv1a32Hex(String content) {
  var hash = 0x811c9dc5;
  for (final codeUnit in content.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toUnsigned(32).toRadixString(16).padLeft(8, '0');
}

String stableSha256Hex(String content, {int length = 64}) {
  final full = crypto.sha256.convert(utf8.encode(content)).toString();
  final safeLength = length.clamp(1, full.length).toInt();
  return full.substring(0, safeLength);
}
