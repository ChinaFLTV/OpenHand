import 'dart:io';

final RegExp _httpUrlWhitespacePattern = RegExp(r'\s');
final RegExp _httpUrlTokenPattern = RegExp(
  r'''https?://[^\s<>"'`\)\]\}）】》〉」』]+''',
  caseSensitive: false,
);

const Set<String> _httpUrlTrailingTokenCharacters = <String>{
  ',',
  '.',
  ';',
  ':',
  '!',
  '?',
  '`',
  '"',
  "'",
  ')',
  ']',
  '}',
  '>',
  '，',
  '。',
  '；',
  '：',
  '！',
  '？',
  '、',
  '）',
  '】',
  '》',
  '〉',
  '」',
  '』',
  '”',
  '’',
  '＂',
  '＇',
};

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

String? firstHttpUrlFromText(String? rawText, {bool allowUserInfo = false}) {
  final text = rawText?.trim();
  if (text == null || text.isEmpty) return null;
  final uris = extractHttpUrisFromText(text, allowUserInfo: allowUserInfo);
  return uris.isEmpty ? null : uris.first.toString();
}

List<Uri> extractHttpUrisFromText(String text, {bool allowUserInfo = false}) {
  final uris = <Uri>[];
  final seen = <String>{};
  for (final source in _httpUrlScanSources(text)) {
    for (final match in _httpUrlTokenPattern.allMatches(source)) {
      final raw = _trimHttpUrlToken(match.group(0) ?? '');
      final uri = tryParseValidHttpUrl(raw, allowUserInfo: allowUserInfo);
      if (uri == null || uri.host.isEmpty) continue;
      final key = uri.toString();
      if (seen.add(key)) uris.add(uri);
    }
  }
  return uris;
}

String _trimHttpUrlToken(String value) {
  var end = value.length;
  while (end > 0) {
    final character = value.substring(end - 1, end);
    if (!_httpUrlTrailingTokenCharacters.contains(character)) break;
    end -= 1;
  }
  return end == value.length ? value : value.substring(0, end);
}

Iterable<String> _httpUrlScanSources(String text) sync* {
  yield text;
  final slashUnescaped = _unescapeForwardSlashes(text);
  if (slashUnescaped != text) yield slashUnescaped;
}

String _unescapeForwardSlashes(String value) {
  var current = value;
  for (var i = 0; i < 4 && current.contains(r'\/'); i += 1) {
    current = current.replaceAll(r'\/', '/');
  }
  return current;
}

String? agentFetchBlockReasonForUri(Uri uri) {
  return agentFetchBlockReasonForHost(uri.host);
}

String? agentFetchBlockReasonForHost(String rawHost) {
  final host = rawHost.trim().toLowerCase();
  if (host.isEmpty) {
    return 'missing or invalid host';
  }
  if (host == 'localhost' || host.endsWith('.localhost')) {
    return 'localhost targets';
  }
  final address = InternetAddress.tryParse(host);
  if (address == null) {
    return null;
  }
  return agentFetchBlockReasonForAddress(address);
}

String? agentFetchBlockReasonForAddress(InternetAddress address) {
  final normalizedAddress = _normalizeMappedInternetAddress(address);
  if (_isUnspecifiedInternetAddress(normalizedAddress)) {
    return 'unspecified addresses';
  }
  if (normalizedAddress.isLoopback) {
    return 'loopback addresses';
  }
  if (normalizedAddress.isLinkLocal) {
    return 'link-local addresses';
  }
  if (normalizedAddress.isMulticast) {
    return 'multicast addresses';
  }
  if (_isPrivateOrReservedInternetAddress(normalizedAddress)) {
    return 'private or reserved network addresses';
  }
  return null;
}

InternetAddress _normalizeMappedInternetAddress(InternetAddress address) {
  if (address.type != InternetAddressType.IPv6) {
    return address;
  }
  final bytes = address.rawAddress;
  final isMappedIpv4 =
      bytes.length == 16 &&
      bytes.sublist(0, 10).every((value) => value == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;
  if (!isMappedIpv4) {
    return address;
  }
  final mappedIpv4 = InternetAddress.tryParse(bytes.sublist(12).join('.'));
  return mappedIpv4 ?? address;
}

bool _isUnspecifiedInternetAddress(InternetAddress address) {
  return address.rawAddress.every((value) => value == 0);
}

bool _isPrivateOrReservedInternetAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    if (bytes.length != 4) {
      return false;
    }
    final first = bytes[0];
    final second = bytes[1];
    return first == 10 ||
        first == 0 ||
        (first == 100 && second >= 64 && second <= 127) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 0 && (bytes[2] == 0 || bytes[2] == 2)) ||
        (first == 192 && second == 168) ||
        (first == 198 && (second == 18 || second == 19)) ||
        (first == 198 && second == 51 && bytes[2] == 100) ||
        (first == 203 && second == 0 && bytes[2] == 113) ||
        first >= 240;
  }
  if (address.type == InternetAddressType.IPv6) {
    if (bytes.length != 16) {
      return false;
    }
    final first = bytes[0];
    final second = bytes[1];
    final isUniqueLocal = (first & 0xfe) == 0xfc;
    final isDeprecatedSiteLocal = first == 0xfe && (second & 0xc0) == 0xc0;
    final isDocumentationRange =
        bytes[0] == 0x20 &&
        bytes[1] == 0x01 &&
        bytes[2] == 0x0d &&
        bytes[3] == 0xb8;
    return isUniqueLocal || isDeprecatedSiteLocal || isDocumentationRange;
  }
  return false;
}
