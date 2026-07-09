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

    test('clamps a trailing wide cell before reflow copies past line data', () {
      final terminal = Terminal();

      terminal
        ..resize(64, 6)
        ..mainBuffer.clear();
      final line = terminal.mainBuffer.lines[0];

      line.setCell(63, '界'.runes.single, 2, CursorStyle.empty);

      expect(line.getTrimmedLength(64), 64);
      expect(() => terminal.resize(65, 6), returnsNormally);
    });

    test(
      'keeps a one-column wide glyph shrink finite',
      () {
        final terminal = Terminal();

        terminal
          ..resize(2, 6)
          ..mainBuffer.clear();
        terminal.mainBuffer.lines[0].setCell(
          0,
          '界'.runes.single,
          2,
          CursorStyle.empty,
        );

        expect(() => terminal.resize(1, 6), returnsNormally);
        expect(terminal.viewWidth, 1);
      },
      timeout: const Timeout(Duration(seconds: 2)),
    );
  });
}

String _lineText(Terminal terminal, int index) {
  return terminal.mainBuffer.lines[index].getText().trimRight();
}
