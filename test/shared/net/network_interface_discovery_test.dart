import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/net/network_interface_discovery.dart';

void main() {
  test('仅保留可对外展示的 IPv4 地址', () {
    final hosts = collectAdvertisableIpv4Hosts(<InternetAddress>[
      InternetAddress('127.0.0.1'),
      InternetAddress('0.0.0.0'),
      InternetAddress('169.254.10.20'),
      InternetAddress('224.0.0.1'),
      InternetAddress('::1'),
      InternetAddress('192.168.1.10'),
    ]);

    expect(hosts, const <String>['192.168.1.10']);
  });

  test('地址去重并按常用局域网网段优先排序', () {
    final hosts = collectAdvertisableIpv4Hosts(<InternetAddress>[
      InternetAddress('8.8.8.8'),
      InternetAddress('172.16.0.2'),
      InternetAddress('10.0.0.2'),
      InternetAddress('192.168.1.2'),
      InternetAddress('10.0.0.2'),
    ]);

    expect(hosts, const <String>[
      '192.168.1.2',
      '10.0.0.2',
      '172.16.0.2',
      '8.8.8.8',
    ]);
  });

  test('地址数量上限无效时直接拒绝', () {
    expect(
      () => collectAdvertisableIpv4Hosts(<InternetAddress>[
        InternetAddress('192.168.1.2'),
      ], maxHosts: 0),
      throwsArgumentError,
    );
  });
}
