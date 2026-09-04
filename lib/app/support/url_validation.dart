import 'dart:async';
import 'dart:io';

import '../../shared/net/loopback_hosts.dart';
import '../../shared/net/network_limits.dart';
import '../../shared/net/tcp_port_utils.dart';
import '../../shared/util/argument_guards.dart';
import '../../shared/util/input_value_parsing.dart';

final RegExp _httpUrlWhitespacePattern = RegExp(r'\s');
final RegExp _httpUrlTokenPattern = RegExp(
  r'''https?://[^\s<>"'`\)\]\}，。；：！？、）】》〉」』＂＇“”‘’]+''',
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
  final trimmed = nullIfBlank(rawValue);
  if (trimmed == null || _httpUrlWhitespacePattern.hasMatch(trimmed)) {
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
  final host = nullIfBlank(uri.host);
  if (host == null ||
      _httpUrlWhitespacePattern.hasMatch(host) ||
      host.contains('%') ||
      (uri.hasPort && !isValidTcpPort(uri.port)) ||
      (!allowUserInfo && nullIfBlank(uri.userInfo) != null)) {
    return null;
  }
  return uri.scheme == scheme ? uri : uri.replace(scheme: scheme);
}

bool isValidHttpUrl(String rawValue, {bool allowUserInfo = false}) {
  return tryParseValidHttpUrl(rawValue, allowUserInfo: allowUserInfo) != null;
}

String? firstHttpUrlFromText(String? rawText, {bool allowUserInfo = false}) {
  final text = nullIfBlank(rawText);
  if (text == null) return null;
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

typedef AgentFetchHostLookup =
    Future<List<InternetAddress>> Function(String host);

const Duration _agentFetchDnsResolutionTimeout = Duration(seconds: 2);

/// 校验 HTTP 地址及其 DNS 解析结果，避免抓取流程访问本机或保留网络。
Future<String?> agentFetchBlockReasonForResolvedUri(
  Uri uri, {
  AgentFetchHostLookup? hostLookup,
  Duration dnsTimeout = _agentFetchDnsResolutionTimeout,
}) async {
  requirePositiveDurationAtMost(
    dnsTimeout,
    kOpenHandMaxNetworkOperationTimeout,
    'dnsTimeout',
  );
  final normalized = normalizeValidHttpUri(uri);
  if (normalized == null) return '无效的 HTTP 地址';
  final directReason = agentFetchBlockReasonForUri(normalized);
  if (directReason != null) return directReason;
  if (InternetAddress.tryParse(normalized.host) != null) return null;
  try {
    final addresses = await (hostLookup ?? InternetAddress.lookup)(
      normalized.host,
    ).timeout(dnsTimeout);
    if (addresses.isEmpty) return 'DNS 未解析到可用地址';
    for (final address in addresses) {
      final addressReason = agentFetchBlockReasonForAddress(address);
      if (addressReason != null) {
        return '$addressReason (${address.address})';
      }
    }
  } on SocketException {
    return 'DNS 解析失败';
  } on TimeoutException {
    return 'DNS 解析超时';
  } catch (_) {
    return 'DNS 解析失败';
  }
  return null;
}

String? agentFetchBlockReasonForHost(String rawHost) {
  final normalized = lowercaseStringFromValue(rawHost);
  final host = normalized.endsWith('.')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  if (host.isEmpty) {
    return '主机缺失或无效';
  }
  if (isLoopbackHostname(host)) {
    return '本机地址';
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
    return '未指定地址';
  }
  if (normalizedAddress.isLoopback) {
    return '回环地址';
  }
  if (normalizedAddress.isLinkLocal) {
    return '链路本地地址';
  }
  if (normalizedAddress.isMulticast) {
    return '组播地址';
  }
  if (_isPrivateOrReservedInternetAddress(normalizedAddress)) {
    return '私有或保留网络地址';
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
