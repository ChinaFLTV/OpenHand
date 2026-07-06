import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_proxy_settings.dart';

void main() {
  group('AppProxySettings', () {
    test('fromJson falls back when payload shape is invalid', () {
      expect(
        AppProxySettings.fromJson('not json'),
        AppProxySettings.defaults(),
      );
      expect(AppProxySettings.fromJson(null), AppProxySettings.defaults());
    });

    test('fromJson normalizes protocols, ports, exceptions and endpoint', () {
      final settings = AppProxySettings.fromJson(<String, Object?>{
        'mode': 'manual',
        'protocols': <Object?>['socks5', 'unknown', 'http', 'https', 'http'],
        'host': '127.0.0.1',
        'port': 70000,
        'auth_enabled': 'yes',
        'exceptions': <Object?>[' localhost ', '', 'api.internal', 'localhost'],
        'test_endpoint': '   ',
      });

      expect(settings.mode, AppProxyMode.manual);
      expect(settings.protocols.toList(), <AppProxyProtocol>[
        AppProxyProtocol.http,
        AppProxyProtocol.https,
        AppProxyProtocol.socks,
      ]);
      expect(settings.port, AppProxySettings.maxPort);
      expect(settings.authEnabled, isTrue);
      expect(settings.exceptions, <String>['localhost', 'api.internal']);
      expect(settings.testEndpoint, AppProxySettings.defaultTestEndpoint);
    });

    test(
      'fromJson restores default protocols and port for unusable values',
      () {
        final settings = AppProxySettings.fromJson(<String, Object?>{
          'protocols': <Object?>['unknown'],
          'port': 'bad',
        });

        expect(settings.protocols, AppProxySettings.defaults().protocols);
        expect(settings.port, AppProxySettings.defaultPort);
      },
    );

    test('copyWith normalizes current and replacement values', () {
      const settings = AppProxySettings(
        mode: AppProxyMode.automatic,
        protocols: <AppProxyProtocol>{AppProxyProtocol.socks},
        host: '',
        port: 0,
        authEnabled: false,
        username: '',
        password: '',
        exceptions: <String>[' one ', 'one', ''],
        testEndpoint: '',
      );

      final normalizedCurrent = settings.copyWith();
      final normalizedReplacement = settings.copyWith(
        protocols: <AppProxyProtocol>{},
        port: 999999,
        exceptions: <String>[' api ', 'api', 'localhost'],
        testEndpoint: '   ',
      );

      expect(normalizedCurrent.port, AppProxySettings.minPort);
      expect(normalizedCurrent.exceptions, <String>['one']);
      expect(
        normalizedCurrent.testEndpoint,
        AppProxySettings.defaultTestEndpoint,
      );
      expect(
        normalizedReplacement.protocols,
        AppProxySettings.defaults().protocols,
      );
      expect(normalizedReplacement.port, AppProxySettings.maxPort);
      expect(normalizedReplacement.exceptions, <String>['api', 'localhost']);
      expect(
        normalizedReplacement.testEndpoint,
        AppProxySettings.defaultTestEndpoint,
      );
    });

    test('toJson serializes normalized values', () {
      const settings = AppProxySettings(
        mode: AppProxyMode.disabled,
        protocols: <AppProxyProtocol>{
          AppProxyProtocol.socks,
          AppProxyProtocol.http,
        },
        host: 'proxy.local',
        port: -1,
        authEnabled: false,
        username: '',
        password: '',
        exceptions: <String>[' api ', 'api', 'localhost'],
        testEndpoint: '',
      );

      final json = settings.toJson();

      expect(json['protocols'], <String>['http', 'socks']);
      expect(json['port'], AppProxySettings.minPort);
      expect(json['exceptions'], <String>['api', 'localhost']);
      expect(json['test_endpoint'], AppProxySettings.defaultTestEndpoint);
    });

    test('hashCode matches order-insensitive protocol equality', () {
      const first = AppProxySettings(
        mode: AppProxyMode.automatic,
        protocols: <AppProxyProtocol>{
          AppProxyProtocol.http,
          AppProxyProtocol.https,
        },
        host: '',
        port: AppProxySettings.defaultPort,
        authEnabled: false,
        username: '',
        password: '',
        exceptions: <String>[],
      );
      const second = AppProxySettings(
        mode: AppProxyMode.automatic,
        protocols: <AppProxyProtocol>{
          AppProxyProtocol.https,
          AppProxyProtocol.http,
        },
        host: '',
        port: AppProxySettings.defaultPort,
        authEnabled: false,
        username: '',
        password: '',
        exceptions: <String>[],
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });
}
