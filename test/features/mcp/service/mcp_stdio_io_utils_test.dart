import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/service/mcp_stdio_io_utils.dart';

void main() {
  group('firstMcpNpxPackageArgIndex', () {
    test('跳过 npx 控制参数并返回包名位置', () {
      expect(
        firstMcpNpxPackageArgIndex(const <String>[
          '--yes',
          '--',
          '@modelcontextprotocol/server-filesystem',
          '/tmp',
        ]),
        2,
      );
    });

    test('没有包名时返回负一', () {
      expect(
        firstMcpNpxPackageArgIndex(const <String>['-y', '--no-install']),
        -1,
      );
    });
  });
}
