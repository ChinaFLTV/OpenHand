import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_proxy_settings.dart';

void main() {
  test('fromJson parses JSON text and loose scalar values', () {
    final settings = AppProxySettings.fromJson('''
      {
        "mode": " manual ",
        "protocols": [" http ", "socks5", "bad"],
        "host": " 127.0.0.1 ",
        "port": "999999",
        "auth_enabled": "yes",
        "username": " user ",
        "password": " pass ",
        "exceptions": [" localhost ", "", null, 42],
        "test_endpoint": " https://example.com/ping "
      }
    ''');

    expect(settings.mode, AppProxyMode.manual);
    expect(settings.protocols, <AppProxyProtocol>{
      AppProxyProtocol.http,
      AppProxyProtocol.socks,
    });
    expect(settings.host, '127.0.0.1');
    expect(settings.port, AppProxySettings.maxPort);
    expect(settings.authEnabled, isTrue);
    expect(settings.username, ' user ');
    expect(settings.password, ' pass ');
    expect(settings.exceptions, <String>['localhost', '42']);
    expect(settings.testEndpoint, 'https://example.com/ping');
  });

  test('fromJson falls back to defaults for unusable input or protocols', () {
    final defaults = AppProxySettings.defaults();

    expect(AppProxySettings.fromJson('[]'), defaults);
    expect(AppProxySettings.fromJson(42), defaults);

    final settings = AppProxySettings.fromJson(<Object?, Object?>{
      'mode': 'off',
      'protocols': <Object?>['bad'],
      'port': '0',
      'test_endpoint': '',
    });

    expect(settings.mode, AppProxyMode.disabled);
    expect(settings.protocols, defaults.protocols);
    expect(settings.port, AppProxySettings.minPort);
    expect(settings.testEndpoint, AppProxySettings.defaultTestEndpoint);
  });
}
