import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/fs/ai_file_mutation_ledger.dart';

import '../../support/test_directory.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory ledgerDirectory;
  late AiFileMutationLedger ledger;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-mutation-ledger-',
    );
    ledgerDirectory = Directory('${temporaryDirectory.path}/ledger');
    ledger = AiFileMutationLedger(rootDirectory: ledgerDirectory.path);
  });

  tearDown(() => deleteTestDirectory(temporaryDirectory));

  Future<FileMutationRecord> record(String sessionId, String content) async {
    final result = await ledger.recordMutation(
      sessionId: sessionId,
      toolCallId: 'call',
      toolName: 'Write',
      filePath: '${temporaryDirectory.path}/file.txt',
      kind: FileMutationKind.modify,
      beforeContent: null,
      afterContent: content,
    );
    expect(result, isNotNull);
    return result!;
  }

  test('blank session cleanup cannot delete the sessions root', () async {
    await record('session-a', 'content');

    await ledger.clearSession('   ');

    expect(await ledger.recordsForSession('session-a'), hasLength(1));
  });

  test('clearAll invalidates records cached in memory', () async {
    await record('session-a', 'content');
    expect(await ledger.recordsForSession('session-a'), hasLength(1));

    await ledger.clearAll();

    expect(await ledger.recordsForSession('session-a'), isEmpty);
  });

  test('unsafe session IDs use distinct bounded directories', () async {
    await record('same/path', 'one');
    await record('same?path', 'two');

    expect(await ledger.recordsForSession('same/path'), hasLength(1));
    expect(await ledger.recordsForSession('same?path'), hasLength(1));
    final sessionDirectories = await Directory(
      '${ledgerDirectory.path}/sessions',
    ).list().where((entity) => entity is Directory).cast<Directory>().toList();
    expect(sessionDirectories, hasLength(2));
  });

  test('bundle import rejects mismatched and path-like blob keys', () async {
    final content = utf8.encode('payload');
    final mismatchedSha = sha256.convert(utf8.encode('other')).toString();
    final imported = await ledger.importBundleJson(
      jsonEncode(<String, Object?>{
        'kind': 'openhand.file_mutation_ledger.bundle',
        'version': 1,
        'blobs_b64': <String, String>{
          '../../escape': base64Encode(content),
          mismatchedSha: base64Encode(content),
        },
        'sessions': const <Object?>[],
      }),
    );

    expect(imported, 0);
    expect(
      await File('${temporaryDirectory.path}/escape.txt').exists(),
      isFalse,
    );
    expect(
      await File(
        '${ledgerDirectory.path}/blobs/${mismatchedSha.substring(0, 2)}/$mismatchedSha.txt',
      ).exists(),
      isFalse,
    );
  });

  test('bounded bundle export and import preserve records and blobs', () async {
    final original = await record('session-a', 'payload');
    final bundle = await ledger.exportBundleJson();
    final importedLedger = AiFileMutationLedger(
      rootDirectory: '${temporaryDirectory.path}/imported-ledger',
    );

    expect(await importedLedger.importBundleJson(bundle), 1);
    final importedRecords = await importedLedger.recordsForSession('session-a');
    expect(importedRecords, hasLength(1));
    expect(importedRecords.single.recordId, original.recordId);
    expect(
      await importedLedger.readBlob(importedRecords.single.afterSha!),
      'payload',
    );
  });

  test('oversized ledgers are never pruned or used for blob GC', () async {
    await record('session-a', 'content');
    await ledger.saveConfig(
      const LedgerConfig(maxVersionsPerFile: 0, autoCleanupDays: 0),
    );
    final ledgerFile = File(
      '${ledgerDirectory.path}/sessions/session-a/ledger.jsonl',
    );
    final handle = await ledgerFile.open(mode: FileMode.write);
    await handle.truncate(64 * 1024 * 1024 + 1);
    await handle.close();
    final blobFile = File(
      '${ledgerDirectory.path}/blobs/00/${List<String>.filled(64, '0').join()}.txt',
    );
    await blobFile.parent.create(recursive: true);
    await blobFile.writeAsString('sentinel');
    final freshLedger = AiFileMutationLedger(
      rootDirectory: ledgerDirectory.path,
    );

    expect(await freshLedger.pruneToMaxVersionsPerFile(1), 0);
    expect(await ledgerFile.length(), 64 * 1024 * 1024 + 1);
    expect(await blobFile.exists(), isTrue);
  });
}
