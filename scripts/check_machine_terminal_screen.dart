import 'dart:io';
import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'machine_terminal_screen',
  source: r'''
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_screen.dart';

void main() {
  test('清屏保留彩色提示符、输入内容和光标，不向终端发送输入', () {
    final terminal = Terminal()..resize(40, 8);
    var sent = '';
    terminal.onOutput = (s) => sent += s;
    terminal.write('旧输出\r\n\x1b[32muser@host > \x1b[0mecho abc\x1b[3D');
    final x = terminal.buffer.cursorX;
    final color = terminal.buffer.currentLine.getForeground(0);
    final snapshot = clearMachineTerminalScreen(terminal);
    expect(terminal.buffer.cursorY, 0);
    expect(terminal.buffer.cursorX, x);
    expect(terminal.buffer.currentLine.getText(), contains('user@host > echo abc'));
    expect(terminal.buffer.currentLine.getForeground(0), color);
    expect(sent, isEmpty);
    expect(snapshot, isNot(contains('旧输出')));
    terminal.write('Z');
    expect(terminal.buffer.currentLine.getText(), contains('echo Zbc'));
  });
  test('清除回滚区且重复清屏稳定，快照可恢复', () {
    final terminal = Terminal()..resize(40, 6);
    terminal.write(List.filled(30, '历史\r\n').join() + '> ');
    final snapshot = clearMachineTerminalScreen(terminal);
    expect(terminal.buffer.scrollBack, 0);
    expect(terminal.buffer.currentLine.getText(), startsWith('> '));
    final again = clearMachineTerminalScreen(terminal);
    expect(again, snapshot);
    final restored = Terminal()..resize(40, 6)..write(snapshot);
    expect(restored.buffer.currentLine.getText(), terminal.buffer.currentLine.getText());
  });
  test('换行输入、宽字符和光标后的内容完整保留', () {
    final terminal = Terminal()..resize(10, 6);
    terminal.write('旧记录\r\n> 中文abcdefghijk\x1b[3D');
    final before = [for (var i = 1; i <= terminal.buffer.cursorY; i++) terminal.buffer.lines[i].getText()].join();
    clearMachineTerminalScreen(terminal);
    final after = [for (var i = 0; i <= terminal.buffer.cursorY; i++) terminal.buffer.lines[i].getText()].join();
    expect(after, before);
    expect(terminal.buffer.scrollBack, 0);
  });
  test('全屏程序保持画面，重启清空时不保留旧提示符', () {
    final terminal = Terminal()..resize(40, 6)..write('\x1b[?1049h编辑器');
    final before = terminal.buffer.currentLine.getText();
    expect(clearMachineTerminalScreen(terminal), isEmpty);
    expect(terminal.buffer.currentLine.getText(), before);
    terminal.write('\x1b[?1049l旧提示符');
    clearMachineTerminalScreen(terminal, preserveInput: false);
    expect(terminal.buffer.currentLine.getText().trim(), isEmpty);
  });
}
''',
);
