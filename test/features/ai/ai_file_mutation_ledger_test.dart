import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/fs/ai_file_mutation_ledger.dart';
import 'package:path/path.dart' as p;

void main() {
  test('file mutation record parsing normalizes persisted sizes', () {
    final record = FileMutationRecord.tryFromJson(<String, Object?>{
      'id': 'record-1',
      'tool_call_id': 'tool-1',
      'tool_name': 'Edit',
      'path': '/tmp/example.txt',
      'kind': 'modify',
      'ts': '2026-01-01T00:00:00Z',
      'before_size': '128',
      'after_size': double.infinity,
    }, sessionId: 'session-1');

    expect(record, isNotNull);
    expect(record!.beforeSize, 128);
    expect(record.afterSize, 0);
  });

  test('file mutation record parsing clamps negative sizes to fallback', () {
    final record = FileMutationRecord.tryFromJson(<String, Object?>{
      'id': 'record-1',
      'path': '/tmp/example.txt',
      'before_size': -1,
      'after_size': 12.7,
    }, sessionId: 'session-1');

    expect(record, isNotNull);
    expect(record!.beforeSize, 0);
    expect(record.afterSize, 12);
  });

  test('ledger config parsing clamps invalid persisted numeric fields', () {
    final config = LedgerConfig.fromJson(<String, Object?>{
      'max_versions_per_file': '999',
      'auto_cleanup_days': double.infinity,
      'mini_diff_max_bytes': -10,
    });

    expect(config.maxVersionsPerFile, LedgerConfig.maxMaxVersionsPerFile);
    expect(config.autoCleanupDays, LedgerConfig.defaultAutoCleanupDays);
    expect(config.miniDiffMaxBytes, LedgerConfig.minMiniDiffMaxBytes);
  });

  test('ledger config loader falls back for non-object json roots', () async {
    final root = await Directory.systemTemp.createTemp(
      'openhand_ledger_config_test_',
    );
    try {
      await File(p.join(root.path, 'config.json')).writeAsString('[]');

      final config = await AiFileMutationLedger(
        rootDirectoryOverride: root.path,
      ).loadConfig();

      expect(config.maxVersionsPerFile, LedgerConfig.defaultMaxVersionsPerFile);
      expect(config.autoCleanupDays, LedgerConfig.defaultAutoCleanupDays);
      expect(config.miniDiffMaxBytes, LedgerConfig.defaultMiniDiffMaxBytes);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'recordsForSession skips non-object and incomplete ledger lines',
    () async {
      const sessionId = 'session-1';
      final root = await Directory.systemTemp.createTemp(
        'openhand_ledger_records_test_',
      );
      try {
        final sessionDir = Directory(p.join(root.path, 'sessions', sessionId));
        await sessionDir.create(recursive: true);
        final ledgerFile = File(p.join(sessionDir.path, 'ledger.jsonl'));
        await ledgerFile.writeAsString(
          <String>[
            '[]',
            '{}',
            jsonEncode(<String, Object?>{
              'id': 'record-1',
              'path': '/tmp/example.txt',
              'kind': 'modify',
              'ts': '2026-01-01T00:00:00Z',
              'before_size': '4',
              'after_size': '8',
            }),
          ].join('\n'),
        );

        final records = await AiFileMutationLedger(
          rootDirectoryOverride: root.path,
        ).recordsForSession(sessionId);

        expect(records, hasLength(1));
        expect(records.single.recordId, 'record-1');
        expect(records.single.beforeSize, 4);
        expect(records.single.afterSize, 8);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
