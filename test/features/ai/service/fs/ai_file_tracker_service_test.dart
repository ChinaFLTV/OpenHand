import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/fs/ai_file_tracker_service.dart';

void main() {
  group('AiFileTrackerService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'openhand_file_tracker_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('rejects content changes inside timestamp tolerance', () async {
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');
      final tracker = AiFileTrackerService();

      await tracker.recordFileRead(file.path);
      final readModified = (await file.stat()).modified;

      await file.writeAsString('bravo\n');
      await file.setLastModified(readModified.add(const Duration(seconds: 1)));

      final error = await tracker.validateSafeToWrite(file.path);

      expect(error, isNotNull);
      expect(error, contains('Re-read the file before editing'));
    });

    test('allows timestamp-only changes when content is unchanged', () async {
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');
      final tracker = AiFileTrackerService();

      await tracker.recordFileRead(file.path);
      final readModified = (await file.stat()).modified;

      await file.setLastModified(readModified.add(const Duration(seconds: 5)));

      final error = await tracker.validateSafeToWrite(file.path);

      expect(error, isNull);
    });

    test(
      'rejects same-size content changes even with restored timestamp',
      () async {
        final file = File('${tempDir.path}/sample.txt');
        await file.writeAsString('alpha\n');
        final tracker = AiFileTrackerService();

        await tracker.recordFileRead(file.path);
        final readModified = (await file.stat()).modified;

        await file.writeAsString('omega\n');
        await file.setLastModified(readModified);

        final error = await tracker.validateSafeToWrite(file.path);

        expect(error, isNotNull);
        expect(error, contains(file.path));
      },
    );

    test('updateAfterWrite clears read result dedup snapshot', () async {
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');
      final tracker = AiFileTrackerService();

      await tracker.recordReadResult(filePath: file.path, offset: 1, limit: 10);
      expect(
        await tracker.isReadResultUnchanged(
          filePath: file.path,
          offset: 1,
          limit: 10,
        ),
        isTrue,
      );

      await tracker.updateAfterWrite(file.path);

      expect(
        await tracker.isReadResultUnchanged(
          filePath: file.path,
          offset: 1,
          limit: 10,
        ),
        isFalse,
      );
    });
  });
}
