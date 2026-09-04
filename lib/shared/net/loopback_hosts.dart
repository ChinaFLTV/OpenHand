import 'dart:io';

/// 本机回环地址集合：代理例外判定中始终直连。
const Set<String> kLoopbackHosts = <String>{'localhost', '127.0.0.1', '::1'};

/// 判断 host 是否为本机回环主机名（不含 IP 字面量）。
bool isLoopbackHostname(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == 'localhost' ||
      normalized == 'localhost.localdomain' ||
      normalized.endsWith('.localhost');
}

/// 判断 host 是否为本机回环地址。
bool isLoopbackHost(String host) {
  var normalized = host.trim().toLowerCase();
  if (normalized.length >= 2 &&
      normalized.startsWith('[') &&
      normalized.endsWith(']')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  if (isLoopbackHostname(normalized)) {
    return true;
  }
  const mappedIpv4Prefix = '::ffff:';
  if (normalized.startsWith(mappedIpv4Prefix)) {
    normalized = normalized.substring(mappedIpv4Prefix.length);
  }
  return InternetAddress.tryParse(normalized)?.isLoopback ?? false;
}
