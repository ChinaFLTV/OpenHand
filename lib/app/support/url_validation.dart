final RegExp _httpUrlWhitespacePattern = RegExp(r'\s');

Uri? tryParseValidHttpUrl(String rawValue, {bool allowUserInfo = false}) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty || _httpUrlWhitespacePattern.hasMatch(trimmed)) {
    return null;
  }
  return normalizeValidHttpUri(
    Uri.tryParse(trimmed),
    allowUserInfo: allowUserInfo,
  );
}

Uri? normalizeValidHttpUri(Uri? uri, {bool allowUserInfo = false}) {
  if (uri == null || !uri.hasScheme) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return null;
  }
  final host = uri.host.trim();
  if (host.isEmpty ||
      _httpUrlWhitespacePattern.hasMatch(host) ||
      host.contains('%') ||
      (!allowUserInfo && uri.userInfo.trim().isNotEmpty)) {
    return null;
  }
  return uri.scheme == scheme ? uri : uri.replace(scheme: scheme);
}

bool isValidHttpUrl(String rawValue, {bool allowUserInfo = false}) {
  return tryParseValidHttpUrl(rawValue, allowUserInfo: allowUserInfo) != null;
}
