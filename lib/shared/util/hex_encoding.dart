/// 将整数低 8 位编码为两位小写十六进制。
String byteToHex(int value) {
  return (value & 0xff).toRadixString(16).padLeft(2, '0');
}

/// 将字节序列编码为小写十六进制，并以 [separator] 连接。
String bytesToHex(Iterable<int> bytes, {String separator = ''}) {
  return bytes.map(byteToHex).join(separator);
}
