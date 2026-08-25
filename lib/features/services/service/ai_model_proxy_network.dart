import '../../../shared/net/network_interface_discovery.dart';

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
    return await discoverAdvertisableIpv4Hosts();
  } catch (_) {
    return const <String>[];
  }
}
