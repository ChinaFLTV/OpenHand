import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_file_mutation_ledger.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('openhand-ledger-test-');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test(
    'gc keeps referenced blobs and ignores fresh atomic temp files',
    () async {
      final ledger = AiFileMutationLedger(rootDirectoryOverride: tempRoot.path);
      final referencedSha = _sha('referenced');
      final unreferencedSha = _sha('unreferenced');
      final freshTempSha = _sha('fresh-temp');

      final referencedBlob = await _writeBlob(tempRoot, referencedSha, 'keep');
      final unreferencedBlob = await _writeBlob(
        tempRoot,
        unreferencedSha,
        'delete',
      );
      final freshTemp = await _writeBlobArtifact(
        tempRoot,
        freshTempSha,
        '.txt.tmp',
        'active-write',
      );
      await _writeLedgerReferencing(tempRoot, referencedSha);

      final result = await ledger.gcUnreferencedBlobs();

      expect(await referencedBlob.exists(), isTrue);
      expect(await unreferencedBlob.exists(), isFalse);
      expect(await freshTemp.exists(), isTrue);
      expect(result.removed, 1);
      expect(result.bytesFreed, utf8.encode('delete').length);
    },
  );

  test('gc removes stale atomic temp artifacts', () async {
    final ledger = AiFileMutationLedger(rootDirectoryOverride: tempRoot.path);
    final staleTempSha = _sha('stale-temp');
    final staleTemp = await _writeBlobArtifact(
      tempRoot,
      staleTempSha,
      '.txt.tmp',
      'stale-write',
    );
    await staleTemp.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );

    final result = await ledger.gcUnreferencedBlobs();

    expect(await staleTemp.exists(), isFalse);
    expect(result.removed, 1);
    expect(result.bytesFreed, utf8.encode('stale-write').length);
  });
}

String _sha(String value) => sha256.convert(utf8.encode(value)).toString();

Future<File> _writeBlob(Directory root, String sha, String content) {
  return _writeBlobArtifact(root, sha, '.txt', content);
}

Future<File> _writeBlobArtifact(
  Directory root,
  String sha,
  String suffix,
  String content,
) async {
  final shardDir = Directory(p.join(root.path, 'blobs', sha.substring(0, 2)));
  await shardDir.create(recursive: true);
  final file = File(p.join(shardDir.path, '$sha$suffix'));
  await file.writeAsString(content, flush: true);
  return file;
}

Future<void> _writeLedgerReferencing(Directory root, String sha) async {
  final sessionDir = Directory(p.join(root.path, 'sessions', 'session-1'));
  await sessionDir.create(recursive: true);
  final ledger = File(p.join(sessionDir.path, 'ledger.jsonl'));
  final record = FileMutationRecord(
    recordId: 'record-1',
    sessionId: 'session-1',
    toolCallId: 'tool-call-1',
    toolName: 'Write',
    filePath: p.join(root.path, 'sample.txt'),
    kind: FileMutationKind.modify,
    createdAt: DateTime.now().toUtc(),
    beforeSha: sha,
    afterSha: null,
    beforeSize: utf8.encode('referenced').length,
    afterSize: 0,
  );
  await ledger.writeAsString('${jsonEncode(record.toJson())}\n', flush: true);
}
