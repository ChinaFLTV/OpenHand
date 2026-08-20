import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/utils/circular_buffer.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('环形缓冲溢出后替换仍保持顺序', () {
    final buffer = IndexAwareCircularBuffer<_TestItem>(4)
      ..push(_TestItem(0))
      ..push(_TestItem(1))
      ..push(_TestItem(2))
      ..push(_TestItem(3))
      ..push(_TestItem(4))
      ..push(_TestItem(5));

    buffer.replaceWith(buffer.toList());

    expect(buffer.toList().map((item) => item.value), <int>[2, 3, 4, 5]);
  });

  test('窄视口大量输出后扩宽保留最新内容顺序', () {
    final terminal = Terminal(maxLines: 24)..resize(8, 4);
    for (var index = 0; index < 32; index++) {
      terminal.write('line-${index.toString().padLeft(2, '0')}-payload\r\n');
    }

    terminal.resize(24, 6);

    final text = terminal.mainBuffer.getText();
    expect(terminal.viewWidth, 24);
    expect(text, contains('line-29-payload\nline-30-payload\nline-31-payload'));
  });

  test('字节模式匹配覆盖最后一个合法起点', () {
    expect(<int>[1, 2, 3].listIndexOf(<int>[2, 3]), 1);
  });
}

class _TestItem with IndexedItem {
  _TestItem(this.value);

  final int value;
}
