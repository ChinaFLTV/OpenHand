import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/bounded_log_buffer.dart';

void main() {
  test('同时限制日志行数和字符总量', () {
    final buffer = BoundedLogBuffer(maxLines: 3, maxCharacters: 6)
      ..add('12')
      ..add('34')
      ..add('56')
      ..add('78');

    expect(buffer.snapshot(), <String>['34', '56', '78']);
    expect(buffer.characterCount, 6);
  });

  test('单行超限时仅保留最新字符', () {
    final buffer = BoundedLogBuffer(maxLines: 2, maxCharacters: 4)
      ..add('abcdef');

    expect(buffer.snapshot(), <String>['cdef']);
    expect(buffer.characterCount, 4);
  });

  test('清空空缓冲不会制造无意义修订', () {
    final buffer = BoundedLogBuffer(maxLines: 2, maxCharacters: 8);
    expect(buffer.revision, 0);

    buffer.clear();
    expect(buffer.revision, 0);

    buffer
      ..add('日志')
      ..clear();
    expect(buffer.revision, 2);
    expect(buffer.isEmpty, isTrue);
  });
}
