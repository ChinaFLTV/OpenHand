import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('sandbox proxy ports normalize invalid and non-finite values', () {
    final settings = AiSandboxSettings.fromJson(<String, Object?>{
      'http_proxy_port': double.infinity,
      'socks_proxy_port': 70000,
    });

    expect(settings.httpProxyPort, 0);
    expect(settings.socksProxyPort, 0);
  });

  test('sandbox proxy ports keep valid persisted values', () {
    final settings = AiSandboxSettings.fromJson(<String, Object?>{
      'http_proxy_port': '8080',
      'socks_proxy_port': 1080,
    });

    expect(settings.httpProxyPort, 8080);
    expect(settings.socksProxyPort, 1080);
  });
}
