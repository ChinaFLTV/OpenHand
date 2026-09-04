/// 将整数低 8 位编码为两位小写十六进制。
String byteToHex(int value) {
  return (value & 0xff).toRadixString(16).padLeft(2, '0');
}

/// 从 ARGB32 取出 RRGGBB 小写十六进制（不含 `#`）。
String rgbHexFromArgb32(int argb) {
  return (argb & 0x00FFFFFF).toRadixString(16).padLeft(6, '0');
}

/// 将字节序列编码为小写十六进制，并以 [separator] 连接。
String bytesToHex(Iterable<int> bytes, {String separator = ''}) {
  return bytes.map(byteToHex).join(separator);
}

final RegExp _lowercaseSha256HexPattern = RegExp(r'^[0-9a-f]{64}$');

/// 是否为小写 SHA-256 十六进制摘要（64 位 `[0-9a-f]`）。
bool isLowercaseSha256Hex(String value) {
  return _lowercaseSha256HexPattern.hasMatch(value);
}

/// [bytesToHex] 的逆操作：解析十六进制串（大小写均可）为字节序列。
/// 长度为奇数或含非十六进制字符时返回 `null`，由调用方给出友好提示，
/// 而不是让 `FormatException` 的原文冒到界面上。
List<int>? hexToBytes(String value) {
  if (value.isEmpty || value.length.isOdd) return null;
  final bytes = <int>[];
  for (var index = 0; index < value.length; index += 2) {
    final byte = int.tryParse(value.substring(index, index + 2), radix: 16);
    if (byte == null) return null;
    bytes.add(byte);
  }
  return bytes;
}
