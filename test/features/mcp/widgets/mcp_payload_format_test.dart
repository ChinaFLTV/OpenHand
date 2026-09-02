import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/widgets/mcp_payload_format.dart';

void main() {
  test('忽略 JSON-RPC 请求 ID 去重同类诊断', () {
    const first =
        '尚未登录 服务端原始响应: '
        '{"jsonrpc":"2.0","id":17,"error":{"code":-32002}}';
    const second =
        '尚未登录 服务端原始响应: '
        '{"jsonrpc":"2.0", "id": 21, "error":{"code":-32002}}';

    expect(mcpDiagnosticsAreEquivalent(first, second), isTrue);
    expect(
      mcpDiagnosticsAreEquivalent(first, second.replaceFirst('-32002', '-1')),
      isFalse,
    );
  });
}
