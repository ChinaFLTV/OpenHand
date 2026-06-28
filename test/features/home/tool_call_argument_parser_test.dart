import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/util/tool_call_argument_parser.dart';

void main() {
  group('parseBashToolCommandFromArguments', () {
    test('reads cmd before command from normal json arguments', () {
      expect(
        parseBashToolCommandFromArguments(
          '{"cmd":" pwd ","command":"ignored"}',
        ),
        'pwd',
      );
    });

    test('recovers values from concatenated json objects', () {
      expect(
        parseBashToolCommandFromArguments(
          '{"cwd":"/tmp/project"}{"command":" flutter test "}',
        ),
        'flutter test',
      );
    });

    test('reads streaming partial string fields as a fallback', () {
      expect(
        parseBashToolCommandFromArguments('{"command":" flutter ana'),
        'flutter ana',
      );
    });

    test('returns empty string for unrecoverable non-object arguments', () {
      expect(parseBashToolCommandFromArguments('[{"cmd":"pwd"}]'), isEmpty);
      expect(parseBashToolCommandFromArguments('{"command":'), isEmpty);
    });
  });

  group('parseBashToolWorkingDirectoryFromArguments', () {
    test('reads working directory before cwd from normalized maps', () {
      expect(
        parseBashToolWorkingDirectoryFromArguments(
          '{"cwd":"/tmp/a","working_directory":" /tmp/b "}',
        ),
        '/tmp/b',
      );
    });

    test('falls back to cwd when working directory is blank', () {
      expect(
        parseBashToolWorkingDirectoryFromArguments(
          '{"working_directory":"  ","cwd":" /tmp/a "}',
        ),
        '/tmp/a',
      );
    });
  });
}
