import 'dart:io';

import '../util/argument_guards.dart';

const Duration kDefaultNetworkInterfaceDiscoveryTimeout = Duration(seconds: 3);
const int kDefaultNetworkInterfaceHostLimit = 64;
const Duration _maxNetworkInterfaceDiscoveryTimeout = Duration(minutes: 1);

Future<List<String>> discoverAdvertisableIpv4Hosts({
  Duration timeout = kDefaultNetworkInterfaceDiscoveryTimeout,
  int maxHosts = kDefaultNetworkInterfaceHostLimit,
}) async {
  requirePositiveDurationAtMost(
    timeout,
    _maxNetworkInterfaceDiscoveryTimeout,
    'timeout',
  );
  requirePositiveInt(maxHosts, 'maxHosts');
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  ).timeout(timeout);
  return collectAdvertisableIpv4Hosts(
    interfaces.expand((interface) => interface.addresses),
    maxHosts: maxHosts,
  );
}

List<String> collectAdvertisableIpv4Hosts(
  Iterable<InternetAddress> addresses, {
  int maxHosts = kDefaultNetworkInterfaceHostLimit,
}) {
  requirePositiveInt(maxHosts, 'maxHosts');
  final hosts = <String>{};
  for (final address in addresses) {
    if (!isAdvertisableIpv4Address(address)) continue;
    hosts.add(address.address);
    if (hosts.length >= maxHosts) break;
  }
  final sorted = hosts.toList(growable: false)
    ..sort((left, right) {
      final priority = _ipv4HostPriority(
        left,
      ).compareTo(_ipv4HostPriority(right));
      return priority == 0 ? left.compareTo(right) : priority;
    });
  return List<String>.unmodifiable(sorted);
}

bool isAdvertisableIpv4Address(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4 || address.isLoopback) {
    return false;
  }
  final bytes = address.rawAddress;
  if (bytes.length != 4 || bytes[0] == 0 || bytes[0] >= 224) return false;
  return !(bytes[0] == 169 && bytes[1] == 254);
}

int _ipv4HostPriority(String host) {
  final bytes = InternetAddress.tryParse(host)?.rawAddress;
  if (bytes == null || bytes.length != 4) return 100;
  if (bytes[0] == 192 && bytes[1] == 168) return 0;
  if (bytes[0] == 10) return 1;
  if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) return 2;
  return 10;
}
