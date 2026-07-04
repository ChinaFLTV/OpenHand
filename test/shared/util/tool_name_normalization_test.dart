import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/tool_name_normalization.dart';

void main() {
  group('normalizeToolNameToken', () {
    test('trims and replaces unsafe characters', () {
      expect(normalizeToolNameToken('  mcp server/tool  '), 'mcp_server_tool');
      expect(normalizeToolNameToken('__Bash!!'), 'Bash');
    });

    test('sanitizes fallback when the value has no safe token', () {
      expect(
        normalizeToolNameToken(' !!! ', fallback: ' fallback tool '),
        'fallback_tool',
      );
      expect(normalizeToolNameToken(' !!! ', fallback: ' /// '), 'tool');
    });
  });

  group('compactToolName', () {
    test('keeps compact names as-is after normalization', () {
      expect(
        compactToolName(prefix: 'mcp server', token: 'read/file'),
        'mcp_server__read_file',
      );
    });

    test('respects very small max lengths', () {
      expect(
        compactToolName(prefix: 'prefix', token: 'token', maxLength: 1).length,
        1,
      );
      expect(
        compactToolName(prefix: 'prefix', token: 'token', maxLength: 8).length,
        lessThanOrEqualTo(8),
      );
    });
  });

  group('appendUniqueToolNameSuffix', () {
    test('appends suffix without exceeding max length', () {
      expect(
        appendUniqueToolNameSuffix('abcdefghij', 12, maxLength: 10),
        'abcdefg_12',
      );
    });
  });
}
