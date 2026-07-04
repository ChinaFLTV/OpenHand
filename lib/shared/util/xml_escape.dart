const int _kAmpersand = 0x26;
const int _kApostrophe = 0x27;
const int _kDoubleQuote = 0x22;
const int _kLessThan = 0x3c;
const int _kGreaterThan = 0x3e;

String escapeXmlText(String value) {
  return _escapeXml(value, escapeAttributeQuotes: false);
}

String escapeXmlAttribute(String value) {
  return _escapeXml(value, escapeAttributeQuotes: true);
}

String _escapeXml(String value, {required bool escapeAttributeQuotes}) {
  StringBuffer? buffer;
  var segmentStart = 0;
  for (var i = 0; i < value.length; i++) {
    final replacement = switch (value.codeUnitAt(i)) {
      _kAmpersand => '&amp;',
      _kLessThan => '&lt;',
      _kGreaterThan => '&gt;',
      _kDoubleQuote when escapeAttributeQuotes => '&quot;',
      _kApostrophe when escapeAttributeQuotes => '&apos;',
      _ => null,
    };
    if (replacement == null) continue;
    buffer ??= StringBuffer();
    if (segmentStart < i) {
      buffer.write(value.substring(segmentStart, i));
    }
    buffer.write(replacement);
    segmentStart = i + 1;
  }
  if (buffer == null) return value;
  if (segmentStart < value.length) {
    buffer.write(value.substring(segmentStart));
  }
  return buffer.toString();
}
