import 'dart:io';
import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final service = await File(
    'lib/features/machine_terminal/machine_terminal_service.dart',
  ).readAsString();
  final ansi = service.substring(
    service.indexOf('final RegExp _ansiCsiPattern'),
    service.indexOf('String _removeMarkerNoise'),
  );
  final panel = await File(
    'lib/features/home/widgets/_home_machine_terminal_panel.dart',
  ).readAsString();
  final viewport = panel.substring(
    panel.indexOf('class _MachineTerminalViewport'),
    panel.indexOf('class _MachineTerminalShell'),
  );
  final constants = panel.substring(
    panel.indexOf('const Color'),
    panel.indexOf('/// 终端画布表面'),
  );
  final theme = panel.substring(
    panel.indexOf('TerminalTheme _machineTerminalTheme'),
    panel.indexOf('Color _terminalStatusColor'),
  );
  await runFlutterWidgetCheck(
    root: File.fromUri(Platform.script).parent.parent,
    name: 'machine_terminal_screen',
    source:
        r'''
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/animated_menu.dart';
import 'package:openhand/shared/ui/openhand_clipboard.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';
import 'package:openhand/shared/util/localized_text.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_service.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_command_protocol.dart';
import 'package:xterm/xterm.dart';
import 'package:openhand/features/machine_terminal/machine_terminal_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('切换终端不继承旧滚动位置，离开后的输出不操作新视口', (tester) async {
    final directory = Directory.systemTemp.createTempSync('terminal-viewport-');
    final service = MachineTerminalService(sessionsDirectoryPath: directory.path);
    final controller = TerminalController();
    final focus = FocusNode();
    await tester.runAsync(() => service.ensureWorkspace(sessionId: 'test', start: false));
    final first = service.activeTerminal('test')!;
    final second = (await tester.runAsync(() => service.newTerminal(sessionId: 'test', start: false)))!;
    first.terminal.write(List.filled(300, '旧终端输出\r\n').join() + 'old > ');
    second.terminal.write('\x1b[32mnew > \x1b[0m');
    Widget view(MachineTerminalSession session) => MaterialApp(home: Scaffold(body: SizedBox(width: 640, height: 320,
      child: _MachineTerminalViewport(key: ValueKey(session.id), session: session, controller: controller, focusNode: focus, padding: const EdgeInsets.all(10)))));
    await tester.pumpWidget(view(first)); await tester.pump();
    final previous = tester.state<_MachineTerminalViewportState>(find.byType(_MachineTerminalViewport));
    previous._scrollController.jumpTo(300);
    await tester.pumpWidget(view(second)); await tester.pump();
    final current = tester.state<_MachineTerminalViewportState>(find.byType(_MachineTerminalViewport));
    expect(identical(previous._scrollController, current._scrollController), isFalse);
    expect(current._scrollController.offset, 0);
    expect(second.terminal.buffer.currentLine.getText(), contains('new >'));
    first.terminal.write('后台输出\r\n');
    second.terminal.write('echo ready');
    await tester.pump();
    expect(current._scrollController.offset, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => service.shutdown());
    service.dispose(); controller.dispose(); focus.dispose(); directory.deleteSync(recursive: true);
  });
  test('OSC 终止符不能吞掉命令标记，增量结果与整段一致', () {
    const raw = '\x1b]7;file://host/project\x1b\\\r\n__BEGIN__\r\nDarwin\r\n__END__:0\r\n\x1b]2;next title\x07';
    final plain = _plainText(raw);
    expect(plain, contains('__BEGIN__\nDarwin\n__END__:0\n'));
    expect(MachineTerminalCommandMarkers('__BEGIN__', '__END__').locate(plain).endIndex, greaterThan(0));
    for (var split = 0; split <= raw.length; split++) {
      final first = raw.substring(0, split);
      final boundary = _ansiSafeSplitLength(first);
      expect(_plainText(first.substring(0, boundary)) + _plainText(raw.substring(boundary)), plain, reason: '分块位置 $split');
    }
  });
  test('删除的终端不能重新启动，失效标识不能落到当前终端', () async {
    final directory = Directory.systemTemp.createTempSync('terminal-lifecycle-');
    final service = MachineTerminalService(sessionsDirectoryPath: directory.path);
    try {
      await service.ensureWorkspace(sessionId: 'test', start: false);
      final terminal = await service.newTerminal(sessionId: 'test', start: false);
      await service.deleteTerminal(sessionId: 'test', terminalId: terminal.id);
      await expectLater(terminal.start(), throwsStateError);
      await expectLater(service.executeCommand(sessionId: 'test', terminalId: terminal.id, command: 'echo test'), throwsStateError);
      await service.closeTerminal(sessionId: 'test', terminalId: terminal.id);
      expect(service.activeTerminal('test')!.status, MachineTerminalStatus.idle);
      final pending = await service.newTerminal(sessionId: 'test');
      await service.deleteTerminal(sessionId: 'test', terminalId: pending.id);
      await Future<void>.delayed(Duration.zero);
      expect(pending.status, MachineTerminalStatus.stopped);
      expect(pending.snapshot().pid, isNull);
    } finally {
      await service.shutdown();
      service.dispose();
      directory.deleteSync(recursive: true);
    }
  });
  test('终端启动提示符按任意数据边界拆分后仍完整显示', () {
    const output = '\x1b]2;host:/project\x07\x1b]7;file://host/project\x1b\\\r\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b[01;32m➜  \x1b[36mproject\x1b[00m \x1b[K\x1b[?1h\x1b=\x1b[?2004h';
    for (var split = 0; split <= output.length; split++) {
      final terminal = Terminal()..resize(74, 28);
      terminal.write(output.substring(0, split));
      terminal.write(output.substring(split));
      expect(terminal.buffer.currentLine.getText(), contains('project'), reason: '分块位置 $split');
    }
  });
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
''' +
        ansi +
        viewport +
        constants +
        theme,
  );
}
