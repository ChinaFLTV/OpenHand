const int mcpHttpHeaderValueMaxCodeUnit = 255;

final RegExp _mcpHttpHeaderNamePattern = RegExp(
  r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$",
);

bool isValidMcpHttpHeaderName(String value) {
  final trimmed = value.trim();
  return trimmed.isNotEmpty && _mcpHttpHeaderNamePattern.hasMatch(trimmed);
}

bool isValidMcpHttpHeaderValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  for (final codeUnit in trimmed.codeUnits) {
    if (codeUnit > mcpHttpHeaderValueMaxCodeUnit) {
      return false;
    }
    if (codeUnit == 0x09) {
      continue;
    }
    if (codeUnit < 0x20 || codeUnit == 0x7F) {
      return false;
    }
  }
  return true;
}

bool isValidMcpHttpHeader(String name, String value) {
  return isValidMcpHttpHeaderName(name) && isValidMcpHttpHeaderValue(value);
}
