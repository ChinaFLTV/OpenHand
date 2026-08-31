import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/net/tcp_port_utils.dart';

void main() {
  group('TCP 端口校验', () {
    test('仅接受标准端口边界', () {
      expect(isValidTcpPort(null), isFalse);
      expect(isValidTcpPort(kTcpPortMin - 1), isFalse);
      expect(isValidTcpPort(kTcpPortMin), isTrue);
      expect(isValidTcpPort(kTcpPortMax), isTrue);
      expect(isValidTcpPort(kTcpPortMax + 1), isFalse);
    });

    test('解析失败时不产生伪造端口', () {
      expect(tcpPortFromValue('443'), 443);
      expect(tcpPortFromValue('443.0'), isNull);
      expect(tcpPortFromValue(true), isNull);
      expect(tcpPortFromText(' 8080 '), 8080);
      expect(tcpPortFromText('0'), isNull);
      expect(tcpPortFromText('65536'), isNull);
    });

    test('钳制和回退行为保持明确', () {
      expect(clampTcpPort(-1), kTcpPortMin);
      expect(clampTcpPort(8080), 8080);
      expect(clampTcpPort(70000), kTcpPortMax);
      expect(tcpPortFromValueOr('bad', fallback: 9000), 9000);
      expect(clampedTcpPortFromValue('bad', fallback: 70000), kTcpPortMax);
    });
  });
}
