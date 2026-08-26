import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/physical_path_safety.dart';
import 'package:path/path.dart' as p;

void main() {
  group('物理路径边界校验', () {
    test('父目录使用符号链接别名时仍识别内部文件', () async {
      final realRoot = await Directory.systemTemp.createTemp(
        'openhand-physical-root-',
      );
      final alias = Link(
        p.join(
          Directory.systemTemp.path,
          'openhand-physical-alias-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      addTearDown(() async {
        if (await alias.exists()) await alias.delete();
        if (await realRoot.exists()) await realRoot.delete(recursive: true);
      });
      await alias.create(realRoot.path);
      final file = File(p.join(alias.path, 'generated.png'));
      await file.writeAsBytes(const <int>[1, 2, 3]);

      expect(await isPhysicalPathWithinOrEqual(alias.path, file.path), isTrue);
    });

    test('拒绝通过目录内符号链接访问外部文件', () async {
      final root = await Directory.systemTemp.createTemp(
        'openhand-physical-root-',
      );
      final outside = await Directory.systemTemp.createTemp(
        'openhand-physical-outside-',
      );
      final escape = Link(p.join(root.path, 'escape'));
      addTearDown(() async {
        if (await escape.exists()) await escape.delete();
        if (await root.exists()) await root.delete(recursive: true);
        if (await outside.exists()) await outside.delete(recursive: true);
      });
      await escape.create(outside.path);
      final file = File(p.join(outside.path, 'private.mp4'));
      await file.writeAsBytes(const <int>[1, 2, 3]);

      expect(
        await isPhysicalPathWithinOrEqual(
          root.path,
          p.join(escape.path, p.basename(file.path)),
        ),
        isFalse,
      );
    });
  });
}
