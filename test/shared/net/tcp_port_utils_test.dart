import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/net/tcp_port_utils.dart';

void main() {
  group('isValidTcpPort', () {
    test('accepts the TCP port range', () {
      expect(isValidTcpPort(kTcpPortMin), isTrue);
      expect(isValidTcpPort(8080), isTrue);
      expect(isValidTcpPort(kTcpPortMax), isTrue);
    });

    test('rejects null and out-of-range ports', () {
      expect(isValidTcpPort(null), isFalse);
      expect(isValidTcpPort(0), isFalse);
      expect(isValidTcpPort(kTcpPortMax + 1), isFalse);
    });
  });

  test('tcpPortFromValueOr falls back for invalid values', () {
    expect(tcpPortFromValueOr('443', fallback: 80), 443);
    expect(tcpPortFromValueOr('0', fallback: 80), 80);
    expect(tcpPortFromValueOr('70000', fallback: 80), 80);
  });

  test('clampedTcpPortFromValue clamps parsed values', () {
    expect(clampedTcpPortFromValue('-1', fallback: 8080), kTcpPortMin);
    expect(clampedTcpPortFromValue('70000', fallback: 8080), kTcpPortMax);
    expect(clampedTcpPortFromValue('bad', fallback: 8080), 8080);
  });

  test('tcpPortFromText parses valid text only', () {
    expect(tcpPortFromText(' 7890 '), 7890);
    expect(tcpPortFromText('0'), isNull);
    expect(tcpPortFromText('65536'), isNull);
  });
}
