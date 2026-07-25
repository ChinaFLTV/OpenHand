import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/bounded_text_buffer.dart';

void main() {
  test('滚动裁剪后仍可按绝对偏移读取增量', () {
    final buffer = BoundedTextBuffer(maxCharacters: 5);

    buffer.append('abc');
    final commandStart = buffer.endOffset;
    buffer.append('def');

    expect(buffer.text, 'bcdef');
    expect(buffer.startOffset, 1);
    expect(buffer.endOffset, 6);
    expect(buffer.textFrom(commandStart), 'def');
    expect(buffer.discardedSince(0), isTrue);
  });

  test('裁剪不会保留残缺的 UTF-16 代理对', () {
    final buffer = BoundedTextBuffer(maxCharacters: 2, initialValue: 'a😀b');

    expect(buffer.text, 'b');
    expect(buffer.text.runes, <int>[0x62]);
    expect(buffer.length, lessThanOrEqualTo(buffer.maxCharacters));
  });

  test('跨分片代理对也不会被滚动边界拆开', () {
    final buffer = BoundedTextBuffer(maxCharacters: 2);

    buffer.append('a\uD83D');
    buffer.append('\uDE00b');

    expect(buffer.text, 'b');
    expect(buffer.text.runes, <int>[0x62]);
  });

  test('替换内容会重置绝对偏移', () {
    final buffer = BoundedTextBuffer(maxCharacters: 4, initialValue: '12345');
    expect(buffer.startOffset, 1);

    buffer.replace('ab');

    expect(buffer.text, 'ab');
    expect(buffer.startOffset, 0);
    expect(buffer.endOffset, 2);
  });

  test('拒绝无效容量', () {
    expect(() => BoundedTextBuffer(maxCharacters: 0), throwsArgumentError);
  });
}
