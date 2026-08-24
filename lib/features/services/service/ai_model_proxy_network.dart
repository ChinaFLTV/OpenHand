import 'dart:io';

const Duration aiModelProxyInterfaceDiscoveryTimeout = Duration(seconds: 3);
const int aiModelProxyMaxDiscoveredHosts = 64;

/// 判断中转站是否监听在通配地址上。
bool isAiModelProxyWildcardListenHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == '*' ||
      normalized == '0.0.0.0' ||
      normalized == '::' ||
      normalized == '::0';
}

/// 发现适合展示给局域网客户端的本机 IPv4 地址。
///
/// 仅在通配监听时执行；发现失败或超时返回空列表，不影响中转站运行。
Future<List<String>> discoverAiModelProxyLanHosts(String listenHost) async {
  if (!isAiModelProxyWildcardListenHost(listenHost)) {
    return const <String>[];
  }
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    ).timeout(aiModelProxyInterfaceDiscoveryTimeout);
    final hosts = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (_isAdvertisableIpv4(address)) hosts.add(address.address);
        if (hosts.length >= aiModelProxyMaxDiscoveredHosts) break;
      }
      if (hosts.length >= aiModelProxyMaxDiscoveredHosts) break;
    }
    final sorted = hosts.toList(growable: false)
      ..sort((left, right) {
        final leftPriority = _lanHostPriority(left);
        final rightPriority = _lanHostPriority(right);
        return leftPriority == rightPriority
            ? left.compareTo(right)
            : leftPriority.compareTo(rightPriority);
      });
    return List<String>.unmodifiable(sorted);
  } catch (_) {
    return const <String>[];
  }
}

bool _isAdvertisableIpv4(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4 || address.isLoopback) {
    return false;
  }
  if (address.rawAddress.every((byte) => byte == 0)) return false;
  final parts = address.address
      .split('.')
      .map((value) => int.tryParse(value) ?? -1)
      .toList(growable: false);
  if (parts.length != 4 || parts.any((value) => value < 0 || value > 255)) {
    return false;
  }
  return parts[0] < 224 && !(parts[0] == 169 && parts[1] == 254);
}

int _lanHostPriority(String host) {
  final parts = host
      .split('.')
      .map((value) => int.tryParse(value) ?? -1)
      .toList(growable: false);
  if (parts.length != 4) return 100;
  if (parts[0] == 192 && parts[1] == 168) return 0;
  if (parts[0] == 10) return 1;
  if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return 2;
  return 10;
}
