/// Lowercase two-digit hex for a single byte. Masks to the low 8 bits so
/// callers can pass raw ints without pre-masking.
String byteToHex(int value) {
  return (value & 0xff).toRadixString(16).padLeft(2, '0');
}

/// Encodes [bytes] as lowercase hex, joining each two-digit group with
/// [separator] (empty by default — e.g. `' '` for a spaced hex dump).
String bytesToHex(Iterable<int> bytes, {String separator = ''}) {
  return bytes.map(byteToHex).join(separator);
}
