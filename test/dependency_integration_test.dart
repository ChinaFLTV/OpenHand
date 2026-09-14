import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openhand/features/ai/service/fs/ai_attachment_service.dart';
import 'package:openhand/shared/db/database_service.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('openhand-dependencies-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('图片附件缩放后保持 PNG 透明度与尺寸信息', () async {
    final source = img.Image(width: 80, height: 40, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(60, 140, 220, 128));
    final input = File('${temporary.path}/透明图片.png');
    await input.writeAsBytes(img.encodePng(source));
    final service = AiAttachmentService(
      attachmentsDirectoryPath: '${temporary.path}/attachments',
    )..maxInlineImageDimension = 40;
    final attachments = await service.importAttachments(
      sessionId: 'session',
      messageId: 'message',
      filePaths: [input.path],
      idGenerator: () => 'image',
    );
    final attachment = attachments.single;
    final stored = await File(attachment.storagePath).readAsBytes();
    final decoded = img.decodePng(stored)!;
    expect((decoded.width, decoded.height), (40, 20));
    expect(decoded.getPixel(10, 10).a, 128);
    expect((attachment.width, attachment.height), (40, 20));
    expect(attachment.sizeBytes, stored.length);
    expect(attachment.mimeType, 'image/png');
  });

  test('WebP 图片附件经后台解码后生成可读取的 JPEG', () async {
    final source = img.Image(width: 32, height: 64);
    img.fill(source, color: img.ColorRgb8(60, 140, 220));
    final input = File('${temporary.path}/图片.webp');
    await input.writeAsBytes(img.encodeWebP(source));
    final service = AiAttachmentService(
      attachmentsDirectoryPath: '${temporary.path}/attachments',
    )..maxInlineImageDimension = 32;
    final attachments = await service.importAttachments(
      sessionId: 'session',
      messageId: 'message',
      filePaths: [input.path],
      idGenerator: () => 'image',
    );
    final attachment = attachments.single;
    final decoded = img.decodeJpg(
      await File(attachment.storagePath).readAsBytes(),
    )!;
    expect((decoded.width, decoded.height), (16, 32));
    expect(decoded.getPixel(8, 16).b, closeTo(220, 5));
    expect(attachment.mimeType, 'image/jpeg');
    expect(attachment.originalSourcePath, input.path);
  });

  test('SQLite 服务完成建表、事务回滚与关闭重开后的持久化', () async {
    final path = '${temporary.path}/openhand.db';
    var service = await DatabaseService.initialize(databasePath: path);
    try {
      final db = service.database;
      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        DatabaseService.schemaVersion,
      );
      expect((await db.rawQuery('PRAGMA integrity_check')).single.values, [
        'ok',
      ]);
      await db.execute('CREATE TABLE dependency_probe (title TEXT NOT NULL)');
      await db.insert('dependency_probe', {'title': '已保存的中文标题'});
      await expectLater(
        db.transaction((transaction) async {
          await transaction.insert('dependency_probe', {'title': '应当回滚'});
          throw StateError('模拟事务失败');
        }),
        throwsStateError,
      );
      await service.close();
      service = await DatabaseService.initialize(databasePath: path);
      expect(await service.database.query('dependency_probe'), [
        {'title': '已保存的中文标题'},
      ]);
    } finally {
      await service.close();
    }
  });
}
