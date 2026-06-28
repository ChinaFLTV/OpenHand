import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/web_gateway_session_metadata.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';

void main() {
  test('readFromSession normalizes loose nested metadata maps', () {
    final loginAt = DateTime.parse('2026-06-28T10:00:00+08:00');
    final metadata = WebGatewaySessionMetadata.readFromSession(
      <String, Object?>{
        webGatewayMetadataKey: <Object?, Object?>{
          webGatewayLoginSourceKey: ' app_mobile ',
          webGatewayDeviceIdKey: ' device-1 ',
          webGatewayDeviceMacKey: ' AA:BB:CC ',
          'login_at': loginAt,
          42: 'extra-value',
        },
      },
    );

    expect(metadata, isNotNull);
    expect(metadata!.loginSource, WebGatewayLoginSource.appMobile);
    expect(metadata.deviceId, 'device-1');
    expect(metadata.deviceMac, 'AA:BB:CC');
    expect(metadata.fingerprint, 'aa:bb:cc');
    expect(metadata.loginAt, DateTime.utc(2026, 6, 28, 2));
    expect(metadata.extra['42'], 'extra-value');
  });

  test('buildLegacyWebGatewayRequestMetadata writes captured time as UTC', () {
    final metadata = buildLegacyWebGatewayRequestMetadata(
      authMetadata: const <String, Object?>{},
      requestMethod: 'POST',
      requestPath: '/api/messages',
      requestId: 7,
      extras: const <String, Object?>{},
      capturedAt: DateTime.parse('2026-06-28T10:00:00+08:00'),
    );

    final context = metadata[webGatewayMetadataKey]! as Map<String, Object?>;
    expect(context['captured_at'], '2026-06-28T02:00:00.000Z');
  });
}
