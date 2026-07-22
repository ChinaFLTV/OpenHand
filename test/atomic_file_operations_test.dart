import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/db/atomic_file_operations.dart';

void main() {
  test('原子文本与字节写入完整替换目标内容', () async {
    final directory = await Directory.systemTemp.createTemp(
      'openhand_atomic_write_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/result.bin');

    await writeFileAtomically(file, '旧内容');
    expect(await file.readAsString(), '旧内容');

    final bytes = List<int>.generate(
      70 * 1024 + 3,
      (index) => index & 0xff,
      growable: false,
    );
    await writeBytesFileAtomically(file, bytes);
    expect(await file.readAsBytes(), bytes);

    await writeBytesFileAtomically(file, const <int>[]);
    expect(await file.length(), 0);
  });
}
