import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';

void main() {
  group('McpServer', () {
    test('stdio summary trims command arguments and drops blanks', () {
      const server = McpServer(
        name: 'Local',
        type: McpServerType.stdio,
        enabled: true,
        command: '  npx  ',
        args: <String>['  -y ', '', '  @modelcontextprotocol/server  '],
      );

      expect(server.summary, 'npx -y @modelcontextprotocol/server');
    });
  });
}
