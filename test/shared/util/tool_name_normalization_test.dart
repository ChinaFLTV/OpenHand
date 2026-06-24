import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/stable_hash.dart';
import 'package:openhand/shared/util/tool_name_normalization.dart';

void main() {
  group('stable FNV-1a hash', () {
    test('keeps known fingerprints stable', () {
      expect(stableFnv1a32Hex(''), '811c9dc5');
      expect(stableFnv1a32Hex('tool.id'), 'cfa93f46');
    });
  });

  group('tool name normalization', () {
    test('normalizes unsupported characters and trims separators', () {
      expect(
        normalizeToolNameToken('  MCP: server/tool!  '),
        'MCP_server_tool',
      );
      expect(normalizeToolNameToken('***'), 'tool');
    });

    test('compacts long names with a stable hash suffix', () {
      final name = compactToolName(
        prefix: 'mcp__server',
        token: 'a very long tool name with spaces and symbols !!!',
        maxLength: 50,
      );

      expect(name.length, lessThanOrEqualTo(50));
      expect(
        name,
        contains(
          stableFnv1a32Hex('a very long tool name with spaces and symbols !!!'),
        ),
      );
    });

    test('appends unique suffix without exceeding max length', () {
      expect(
        appendUniqueToolNameSuffix(
          'abcdefghijklmnopqrstuvwxyz',
          12,
          maxLength: 16,
        ),
        'abcdefghijklm_12',
      );
    });
  });
}
