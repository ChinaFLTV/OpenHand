import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/tool_call_argument_parser.dart';

void main() {
  group('parseBashToolCommandFromArguments', () {
    test('decodes plain JSON object', () {
      final cmd = parseBashToolCommandFromArguments('{"cmd":"ls -la"}');
      expect(cmd, 'ls -la');
    });

    test('falls back to "command" when "cmd" missing', () {
      final cmd = parseBashToolCommandFromArguments('{"command":"echo hi"}');
      expect(cmd, 'echo hi');
    });

    test(
      'recovers from concatenated JSON objects produced by some upstream '
      'OpenAI-compatible providers (regression for `}{` bug)',
      () {
        const raw =
            '{"working_directory":"/Users/x/Public/FlutterProjects/OpenHand"}'
            '{"cmd":"osascript -e \'delay 0.1\'"}';
        final cmd = parseBashToolCommandFromArguments(raw);
        expect(cmd, "osascript -e 'delay 0.1'");
      },
    );

    test(
      'concatenated objects path also resolves working_directory',
      () {
        const raw = '{"working_directory":"/repo"}{"cmd":"ls"}';
        expect(parseBashToolWorkingDirectoryFromArguments(raw), '/repo');
        expect(parseBashToolCommandFromArguments(raw), 'ls');
      },
    );

    test('returns empty for blank input without throwing', () {
      expect(parseBashToolCommandFromArguments(''), '');
      expect(parseBashToolCommandFromArguments('   '), '');
    });

    test('partial-stream JSON (still streaming) is read via fallback', () {
      // Truncated mid-stream — no closing brace yet.
      const raw = '{"cmd":"echo partial';
      expect(parseBashToolCommandFromArguments(raw), 'echo partial');
    });

    test('handles escaped quotes inside concatenated objects', () {
      const raw = '{"cwd":"/p"}{"cmd":"echo \\"hi\\""}';
      expect(parseBashToolCommandFromArguments(raw), 'echo "hi"');
    });

    test('non-recoverable garbage falls back to partial scan, no throw', () {
      const raw = 'totally not json but contains "cmd": "x"';
      // partial scanner is permissive; just assert no crash.
      expect(() => parseBashToolCommandFromArguments(raw), returnsNormally);
    });
  });
}
