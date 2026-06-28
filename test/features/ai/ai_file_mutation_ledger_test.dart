import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/fs/ai_file_mutation_ledger.dart';

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
}
