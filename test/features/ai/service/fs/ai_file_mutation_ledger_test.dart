import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/fs/ai_file_mutation_ledger.dart';

void main() {
  group('LedgerConfig', () {
    test('fromJson clamps resource retention settings', () {
      final config = LedgerConfig.fromJson(<String, Object?>{
        'max_versions_per_file': 9999,
        'auto_cleanup_days': -5,
        'mini_diff_max_bytes': 999999999,
      });

      expect(config.maxVersionsPerFile, LedgerConfig.maxMaxVersionsPerFile);
      expect(config.autoCleanupDays, LedgerConfig.minAutoCleanupDays);
      expect(config.miniDiffMaxBytes, LedgerConfig.maxMiniDiffMaxBytes);
    });

    test('fromJson falls back malformed values', () {
      final config = LedgerConfig.fromJson(<String, Object?>{
        'max_versions_per_file': 'bad',
        'auto_cleanup_days': 'bad',
        'mini_diff_max_bytes': 'bad',
      });

      expect(config.maxVersionsPerFile, LedgerConfig.defaultMaxVersionsPerFile);
      expect(config.autoCleanupDays, LedgerConfig.defaultAutoCleanupDays);
      expect(config.miniDiffMaxBytes, LedgerConfig.defaultMiniDiffMaxBytes);
    });

    test('copyWith and toJson normalize unsafe values', () {
      const config = LedgerConfig(
        maxVersionsPerFile: 9999,
        autoCleanupDays: 9999,
        miniDiffMaxBytes: -5,
      );
      final copied = config.copyWith();
      final json = config.toJson();

      expect(copied.maxVersionsPerFile, LedgerConfig.maxMaxVersionsPerFile);
      expect(copied.autoCleanupDays, LedgerConfig.maxAutoCleanupDays);
      expect(copied.miniDiffMaxBytes, LedgerConfig.minMiniDiffMaxBytes);
      expect(json['max_versions_per_file'], LedgerConfig.maxMaxVersionsPerFile);
      expect(json['auto_cleanup_days'], LedgerConfig.maxAutoCleanupDays);
      expect(json['mini_diff_max_bytes'], LedgerConfig.minMiniDiffMaxBytes);
    });
  });
}
