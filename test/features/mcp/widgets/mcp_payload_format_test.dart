import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/widgets/mcp_payload_format.dart';

void main() {
  group('MCP 审批载荷格式化', () {
    test('解析宽松对象并保留标量类型', () {
      expect(
        parseMcpLoosePayloadMap('{count: 3, enabled: true, note: ready}'),
        <String, Object?>{'count': 3, 'enabled': true, 'note': 'ready'},
      );
    });

    test('拒绝非对象文本并识别等宽内容', () {
      expect(parseMcpLoosePayloadMap('count: 3'), isNull);
      expect(mcpPayloadPrefersMonospace('command', 'dart test'), isTrue);
      expect(mcpPayloadPrefersMonospace('note', 'ready'), isFalse);
    });
  });
}
