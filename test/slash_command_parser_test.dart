import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/home/slash_command_parser.dart';

void main() {
  test('parseOpenHandSlashCommand parses supported commands', () {
    final help = parseOpenHandSlashCommand('/help');
    final commands = parseOpenHandSlashCommand('/commands');
    final feedback = parseOpenHandSlashCommand('/feedback app freezes');
    final status = parseOpenHandSlashCommand('/status');
    final newSession = parseOpenHandSlashCommand('/new');
    final stop = parseOpenHandSlashCommand('/stop');
    final abort = parseOpenHandSlashCommand('/abort');
    final config = parseOpenHandSlashCommand('/config');
    final sessions = parseOpenHandSlashCommand('/sessions');
    final automations = parseOpenHandSlashCommand('/automations');
    final mcp = parseOpenHandSlashCommand('/mcp');

    expect(help?.kind, OpenHandSlashCommandKind.help);
    expect(commands?.kind, OpenHandSlashCommandKind.help);
    expect(feedback?.kind, OpenHandSlashCommandKind.feedback);
    expect(feedback?.argument, 'app freezes');
    expect(status?.kind, OpenHandSlashCommandKind.status);
    expect(newSession?.kind, OpenHandSlashCommandKind.newSession);
    expect(stop?.kind, OpenHandSlashCommandKind.stop);
    expect(abort?.kind, OpenHandSlashCommandKind.stop);
    expect(config?.kind, OpenHandSlashCommandKind.settings);
    expect(sessions?.kind, OpenHandSlashCommandKind.workspace);
    expect(automations?.kind, OpenHandSlashCommandKind.automations);
    expect(mcp?.kind, OpenHandSlashCommandKind.mcp);
  });

  test(
    'parseOpenHandSlashCommand ignores non-commands and unknown commands',
    () {
      expect(parseOpenHandSlashCommand('hello'), isNull);
      expect(parseOpenHandSlashCommand('/unknown'), isNull);
    },
  );
}
