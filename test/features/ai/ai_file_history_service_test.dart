import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/fs/ai_file_history_service.dart';
import 'package:openhand/shared/util/rolling_hash.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory historyDirectory;
  late File sourceFile;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-file-history-',
    );
    historyDirectory = Directory('${temporaryDirectory.path}/history');
    sourceFile = File('${temporaryDirectory.path}/source.txt');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'saved versions use safe unique IDs and report UTF-8 byte size',
    () async {
      final service = AiFileHistoryService(
        historyDirectory: historyDirectory.path,
      );
      await sourceFile.writeAsString('\u4f60');

      final first = await service.saveVersion(
        filePath: sourceFile.path,
        sessionId: 'session',
        toolCallId: '../unsafe/id',
      );
      final second = await service.saveVersion(
        filePath: sourceFile.path,
        sessionId: 'session',
        toolCallId: '../unsafe/id',
      );
      final versions = await service.getVersionHistory(sourceFile.path);

      expect(first, isNotNull);
      expect(second, isNot(first));
      expect(first, isNot(contains('/')));
      expect(first, isNot(contains(r'\')));
      expect(versions, hasLength(2));
      expect(versions.every((version) => version.fileSizeBytes == 3), isTrue);
    },
  );

  test('rollback rejects traversal and restores a validated version', () async {
    final service = AiFileHistoryService(
      historyDirectory: historyDirectory.path,
    );
    await sourceFile.writeAsString('before');
    final versionId = await service.saveVersion(
      filePath: sourceFile.path,
      sessionId: 'session',
    );
    await sourceFile.writeAsString('after');

    final rejected = await service.rollbackToVersion(
      filePath: sourceFile.path,
      versionId: '../outside',
    );
    expect(rejected.success, isFalse);
    expect(await sourceFile.readAsString(), 'after');

    final restored = await service.rollbackToVersion(
      filePath: sourceFile.path,
      versionId: versionId!,
    );
    expect(restored.success, isTrue);
    expect(await sourceFile.readAsString(), 'before');
  });

  test('invalid retention limits fail fast', () {
    expect(
      () => AiFileHistoryService(
        historyDirectory: historyDirectory.path,
        maxVersionsPerFile: 0,
      ),
      throwsArgumentError,
    );
  });

  test('legacy rolling-hash history directories remain readable', () async {
    await sourceFile.writeAsString('current');
    final normalizedPath = sourceFile.path;
    final legacyHash = rollingHashPositive31Bit(
      normalizedPath.codeUnits,
      (codeUnit) => codeUnit,
    );
    const versionId = '123_manual';
    final legacyDirectory = Directory(
      '${historyDirectory.path}/source_$legacyHash',
    );
    await legacyDirectory.create(recursive: true);
    await File(
      '${legacyDirectory.path}/$versionId.content',
    ).writeAsString('legacy');
    await File('${legacyDirectory.path}/$versionId.meta.json').writeAsString(
      jsonEncode(<String, Object?>{
        'version_id': versionId,
        'file_path': normalizedPath,
        'session_id': 'legacy-session',
        'created_at': DateTime.utc(2025).toIso8601String(),
        'file_size_bytes': 6,
      }),
    );
    final service = AiFileHistoryService(
      historyDirectory: historyDirectory.path,
    );

    expect(await service.getVersionHistory(sourceFile.path), hasLength(1));
    final (content, metadata) = await service.readVersionContent(
      filePath: sourceFile.path,
      versionId: versionId,
    );
    expect(content, 'legacy');
    expect(metadata?.sessionId, 'legacy-session');
  });
}
