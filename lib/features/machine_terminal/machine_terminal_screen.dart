import 'package:xterm/xterm.dart';

/// 仅整理显示缓冲区，不向 PTY 发送按键或执行命令。
String clearMachineTerminalScreen(
  Terminal terminal, {
  bool preserveInput = true,
}) {
  final buffer = terminal.buffer;
  if (terminal.isUsingAltBuffer && preserveInput) {
    terminal.mainBuffer.clearScrollback();
    terminal.write('');
    return '';
  }
  final output = StringBuffer('\x1b[0m\x1b[2J\x1b[H');
  final cursor = buffer.absoluteCursorY;
  var start = cursor;
  var end = cursor;
  if (preserveInput) {
    while (start > 0 &&
        buffer.lines[start].isWrapped &&
        cursor - start < terminal.viewHeight - 1) {
      start--;
    }
    while (end + 1 < buffer.lines.length &&
        buffer.lines[end + 1].isWrapped &&
        end - start < terminal.viewHeight - 1) {
      end++;
    }
    (int, int, int)? style;
    for (var row = start; row <= end; row++) {
      final line = buffer.lines[row];
      var length = line.length;
      if (row == end) {
        while (length > 0 && line.getCodePoint(length - 1) == 0) {
          length--;
        }
      }
      for (var col = 0; col < length; col++) {
        final point = line.getCodePoint(col);
        if (point == 0 && col > 0 && line.getWidth(col - 1) == 2) continue;
        final next = (
          line.getForeground(col),
          line.getBackground(col),
          line.getAttributes(col),
        );
        if (style != next) {
          output.write(_screenStyle(next.$1, next.$2, next.$3));
          style = next;
        }
        output.writeCharCode(point == 0 ? 32 : point);
      }
    }
    output.write('\x1b[${cursor - start + 1};${buffer.cursorX + 1}H');
  }
  output.write(
    _screenStyle(
      terminal.cursor.foreground,
      terminal.cursor.background,
      terminal.cursor.attrs,
    ),
  );
  final snapshot = output.toString();
  buffer.clear();
  terminal.write(snapshot);
  return snapshot;
}

String _screenStyle(int foreground, int background, int flags) {
  final codes = <int>[0];
  const attributes = {
    CellAttr.bold: 1,
    CellAttr.faint: 2,
    CellAttr.italic: 3,
    CellAttr.underline: 4,
    CellAttr.blink: 5,
    CellAttr.inverse: 7,
    CellAttr.invisible: 8,
    CellAttr.strikethrough: 9,
  };
  for (final entry in attributes.entries) {
    if (flags & entry.key != 0) codes.add(entry.value);
  }
  for (final entry in [(foreground, 38), (background, 48)]) {
    final value = entry.$1 & CellColor.valueMask;
    switch (entry.$1 & CellColor.typeMask) {
      case CellColor.named:
        codes.add(
          (entry.$2 == 38 ? 30 : 40) + (value < 8 ? value : value + 52),
        );
      case CellColor.palette:
        codes.addAll([entry.$2, 5, value]);
      case CellColor.rgb:
        codes.addAll([
          entry.$2,
          2,
          value >> 16 & 255,
          value >> 8 & 255,
          value & 255,
        ]);
    }
  }
  return '\x1b[${codes.join(';')}m';
}
