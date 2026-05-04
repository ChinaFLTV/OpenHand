import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/service/web_gateway_accessible_urls.dart';

void main() {
  group('computeWebGatewayAccessibleUrls', () {
    test('未启动现场：boundPort == null → 空列表', () {
      final urls = computeWebGatewayAccessibleUrls(
        listenHost: '0.0.0.0',
        boundPort: null,
        localIPv4Addresses: const <String>['192.168.1.5'],
      );
      expect(urls, isEmpty);
    });

    test('未启动现场：监听具体 IP 但 boundPort==null 仍返回空', () {
      final urls = computeWebGatewayAccessibleUrls(
        listenHost: '127.0.0.1',
        boundPort: null,
        localIPv4Addresses: const <String>[],
      );
      expect(urls, isEmpty);
    });

    test('具体 IP 现场：仅返回 boundUrl，不掺杂 localhost / LAN', () {
      final urls = computeWebGatewayAccessibleUrls(
        listenHost: '192.168.1.5',
        boundPort: 8848,
        localIPv4Addresses: const <String>['10.0.0.7', '192.168.1.5'],
      );
      expect(urls, equals(<String>['http://192.168.1.5:8848']));
    });

    test('具体 IP 现场：listenHost 含前后空白也能正确拼接', () {
      final urls = computeWebGatewayAccessibleUrls(
        listenHost: '  127.0.0.1 ',
        boundPort: 9000,
        localIPv4Addresses: const <String>[],
      );
      expect(urls, equals(<String>['http://127.0.0.1:9000']));
    });

    test('wildcard 现场（0.0.0.0）：无 LAN 时只含 localhost + 127.0.0.1', () {
      final urls = computeWebGatewayAccessibleUrls(
        listenHost: '0.0.0.0',
        boundPort: 7890,
        localIPv4Addresses: const <String>[],
      );
      expect(urls, containsAll(<String>[
        'http://localhost:7890',
        'http://127.0.0.1:7890',
      ]));
      expect(urls.length, 2);
    });

    test('wildcard 现场：枚举出 LAN IP 并去重，跳过空字符串', () {
      final urls = computeWebGatewayAccessibleUrls(
        listenHost: '0.0.0.0',
        boundPort: 7890,
        localIPv4Addresses: const <String>[
          '192.168.1.5',
          '',
          '10.0.0.7',
          '192.168.1.5', // 重复项必须去重
        ],
      );
      expect(urls, containsAll(<String>[
        'http://localhost:7890',
        'http://127.0.0.1:7890',
        'http://192.168.1.5:7890',
        'http://10.0.0.7:7890',
      ]));
      expect(urls.length, 4);
    });

    test('wildcard 现场：空字符串 listenHost 同样按通配符处理', () {
      final urls = computeWebGatewayAccessibleUrls(
        listenHost: '',
        boundPort: 7890,
        localIPv4Addresses: const <String>['192.168.1.5'],
      );
      expect(urls, contains('http://localhost:7890'));
      expect(urls, contains('http://127.0.0.1:7890'));
      expect(urls, contains('http://192.168.1.5:7890'));
    });

    test('wildcard 现场：IPv6 :: 与 ::0 也按通配符处理', () {
      for (final host in <String>['::', '::0']) {
        final urls = computeWebGatewayAccessibleUrls(
          listenHost: host,
          boundPort: 7890,
          localIPv4Addresses: const <String>[],
        );
        expect(urls, containsAll(<String>[
          'http://localhost:7890',
          'http://127.0.0.1:7890',
        ]));
      }
    });

    test('返回的 List 不可被外部修改（unmodifiable 契约）', () {
      final urls = computeWebGatewayAccessibleUrls(
        listenHost: '0.0.0.0',
        boundPort: 7890,
        localIPv4Addresses: const <String>['192.168.1.5'],
      );
      expect(() => urls.add('http://evil:1'), throwsUnsupportedError);
      final urls2 = computeWebGatewayAccessibleUrls(
        listenHost: '127.0.0.1',
        boundPort: 7890,
        localIPv4Addresses: const <String>[],
      );
      expect(() => urls2.removeAt(0), throwsUnsupportedError);
    });
  });
}
