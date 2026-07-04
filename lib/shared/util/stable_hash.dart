import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

const int kStableFnv1a32OffsetBasis = 0x811c9dc5;
const int kStableFnv1a32Prime = 0x01000193;
const int kStableFnv1a32Mask = 0xffffffff;
const int kStableSha256HexLength = 64;

String stableFnv1a32Hex(String content) {
  var hash = kStableFnv1a32OffsetBasis;
  for (final codeUnit in content.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * kStableFnv1a32Prime) & kStableFnv1a32Mask;
  }
  return hash.toUnsigned(32).toRadixString(16).padLeft(8, '0');
}

String stableSha256Hex(String content, {int length = kStableSha256HexLength}) {
  final full = crypto.sha256.convert(utf8.encode(content)).toString();
  final safeLength = length.clamp(1, full.length).toInt();
  return full.substring(0, safeLength);
}
