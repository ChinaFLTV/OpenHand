import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/fs/ai_file_history_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('file history metadata tolerates dirty persisted values', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'openhand_file_history_test_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final target = File(p.join(tempDir.path, 'sample.txt'));
    await target.writeAsString('before edit');
    final historyDir = p.join(tempDir.path, 'history');
    final service = AiFileHistoryService(historyDirectory: historyDir);

    final versionId = await service.saveVersion(
      filePath: target.path,
      sessionId: 'session-a',
      toolCallId: 'tool-a',
    );
    expect(versionId, isNotNull);

    final metaFile = await _findHistoryFile(historyDir, '$versionId.meta.json');
    final contentFile = await _findHistoryFile(
      historyDir,
      '$versionId.content',
    );
    expect(metaFile, isNotNull);
    expect(contentFile, isNotNull);

    await metaFile!.writeAsString(
      jsonEncode(<String, Object?>{
        'version_id': versionId,
        'file_path': target.path,
        'session_id': 'session-a',
        'created_at': '2026-06-28T00:00:00Z',
        'tool_call_id': 42,
        'file_size_bytes': '11',
      }),
    );
    await File(p.join(metaFile.parent.path, 'broken.meta.json')).writeAsString(
      jsonEncode(<String, Object?>{
        'file_path': target.path,
        'session_id': 'session-a',
      }),
    );

    final versions = await service.getVersionHistory(target.path);
    expect(versions, hasLength(1));
    expect(versions.single.versionId, versionId);
    expect(versions.single.toolCallId, '42');
    expect(versions.single.fileSizeBytes, 11);

    final (content, metadata) = await service.readVersionContent(
      filePath: target.path,
      versionId: versionId!,
    );
    expect(content, 'before edit');
    expect(metadata?.fileSizeBytes, 11);

    await service.clearSessionHistory('session-a');
    expect(await metaFile.exists(), isFalse);
    expect(await contentFile!.exists(), isFalse);
  });
}

Future<File?> _findHistoryFile(String root, String basename) async {
  final dir = Directory(root);
  if (!await dir.exists()) return null;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File && p.basename(entity.path) == basename) return entity;
  }
  return null;
}
