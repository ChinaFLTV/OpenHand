import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/tool_call_argument_parser.dart';

void main() {
  test('parseBashToolCommandFromArguments reads complete JSON payloads', () {
    const rawArguments =
        '{"cmd":"pwd","working_directory":"/tmp/openhand-demo"}';

    expect(parseBashToolCommandFromArguments(rawArguments), 'pwd');
    expect(
      parseBashToolWorkingDirectoryFromArguments(rawArguments),
      '/tmp/openhand-demo',
    );
  });

  test(
    'parseBashToolCommandFromArguments extracts partial streamed JSON safely',
    () {
      const rawArguments =
          '{"cmd":"cd particle_web_project && cat > particle_showcase.html << \'EOF\'\\n<!DOCTYPE html>\\n<html lang=\\"zh-CN\\">\\n';

      expect(
        parseBashToolCommandFromArguments(rawArguments),
        contains(
          "cd particle_web_project && cat > particle_showcase.html << 'EOF'",
        ),
      );
      expect(
        parseBashToolCommandFromArguments(rawArguments),
        contains('<!DOCTYPE html>'),
      );
    },
  );

  test(
    'parseBashToolWorkingDirectoryFromArguments extracts partial cwd field',
    () {
      const rawArguments = '{"cwd":"./particle_web_project';

      expect(
        parseBashToolWorkingDirectoryFromArguments(rawArguments),
        './particle_web_project',
      );
    },
  );

  test(
    'parseBashToolCommandFromArguments returns empty for unrelated payloads',
    () {
      const rawArguments = '{"foo":"bar"}';

      expect(parseBashToolCommandFromArguments(rawArguments), isEmpty);
      expect(parseBashToolWorkingDirectoryFromArguments(rawArguments), isEmpty);
    },
  );
}
