import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/index.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('MachineTerminalSession resize', () {
    test('reflows wrapped content when the viewport grows again', () {
      final session = MachineTerminalSession(
        id: 'term-test',
        sessionId: 'session-test',
        identity: 'machine-term-test',
        shell: '/bin/sh',
        workingDirectory: '/',
        onChanged: () {},
      );
      addTearDown(session.dispose);

      final terminal = session.terminal;
      expect(terminal.reflowEnabled, isTrue);

      terminal
        ..resize(24, 6)
        ..mainBuffer.clear()
        ..setCursor(0, 0)
        ..write('abcdefghijklmnopqr');

      expect(_lineText(terminal, 0), 'abcdefghijklmnopqr');

      terminal.resize(12, 6);
      expect(_lineText(terminal, 0), 'abcdefghijkl');
      expect(_lineText(terminal, 1), 'mnopqr');

      terminal.resize(24, 6);
      expect(_lineText(terminal, 0), 'abcdefghijklmnopqr');
      expect(_lineText(terminal, 1), isEmpty);
    });
  });
}

String _lineText(Terminal terminal, int index) {
  return terminal.mainBuffer.lines[index].getText().trimRight();
}
