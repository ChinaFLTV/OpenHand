import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/model/cron_config.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/input_value_parsing.dart';

/// Persistence layer for cron jobs and execution history using SQLite.
class CronsStore {
  CronsStore();

  static const String _tableName = 'cron_jobs';
  static const String _historyTable = 'cron_execution_history';

  Database get _db => DatabaseService.instance.database;

  /// Ensures both tables exist. Call once at startup.
  Future<void> ensureTable() async {
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id                      TEXT PRIMARY KEY,
        name                    TEXT NOT NULL DEFAULT '',
        description             TEXT NOT NULL DEFAULT '',
        script_type             TEXT NOT NULL DEFAULT 'command',
        script_path             TEXT NOT NULL DEFAULT '',
        script_content          TEXT NOT NULL DEFAULT '',
        cron_expression         TEXT NOT NULL DEFAULT '* * * * *',
        retry_count             INTEGER NOT NULL DEFAULT $kCronDefaultRetryCount,
        timeout_seconds         INTEGER NOT NULL DEFAULT $kCronDefaultTimeoutSeconds,
        run_as_user             TEXT NOT NULL DEFAULT '',
        tags                    TEXT NOT NULL DEFAULT '',
        enabled                 INTEGER NOT NULL DEFAULT 1,
        status                  TEXT NOT NULL DEFAULT 'idle',
        on_success_notify       TEXT NOT NULL DEFAULT 'log',
        on_failure_notify       TEXT NOT NULL DEFAULT 'system',
        on_timeout_notify       TEXT NOT NULL DEFAULT 'system',
        on_success_severity     TEXT NOT NULL DEFAULT 'success',
        on_failure_severity     TEXT NOT NULL DEFAULT 'error',
        on_timeout_severity     TEXT NOT NULL DEFAULT 'warning',
        on_success_play_sound   INTEGER NOT NULL DEFAULT 0,
        on_failure_play_sound   INTEGER NOT NULL DEFAULT 1,
        on_timeout_play_sound   INTEGER NOT NULL DEFAULT 1,
        on_success_vibrate      INTEGER NOT NULL DEFAULT 0,
        on_failure_vibrate      INTEGER NOT NULL DEFAULT 1,
        on_timeout_vibrate      INTEGER NOT NULL DEFAULT 1,
        on_success_message      TEXT NOT NULL DEFAULT '',
        on_failure_message      TEXT NOT NULL DEFAULT '',
        on_timeout_message      TEXT NOT NULL DEFAULT '',
        collect_app_metadata    INTEGER NOT NULL DEFAULT 1,
        collect_host_metadata   INTEGER NOT NULL DEFAULT 1,
        collect_environment_snapshot INTEGER NOT NULL DEFAULT 0,
        working_directory       TEXT NOT NULL DEFAULT '',
        environment             TEXT NOT NULL DEFAULT '',
        max_retry_delay_seconds INTEGER NOT NULL DEFAULT $kCronDefaultRetryDelaySeconds,
        last_run_at             TEXT NOT NULL DEFAULT '',
        next_run_at             TEXT NOT NULL DEFAULT '',
        last_exit_code          INTEGER,
        consecutive_failures    INTEGER NOT NULL DEFAULT 0,
        created_at              TEXT NOT NULL DEFAULT '',
        updated_at              TEXT NOT NULL DEFAULT '',
        sort_order              INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _db.execute('''
      CREATE TABLE IF NOT EXISTS $_historyTable (
        id                TEXT PRIMARY KEY,
        cron_id           TEXT NOT NULL,
        started_at        TEXT NOT NULL,
        finished_at       TEXT NOT NULL DEFAULT '',
        status            TEXT NOT NULL DEFAULT 'running',
        exit_code         INTEGER,
        stdout            TEXT NOT NULL DEFAULT '',
        stderr            TEXT NOT NULL DEFAULT '',
        error_message     TEXT NOT NULL DEFAULT '',
        elapsed_ms        INTEGER NOT NULL DEFAULT 0,
        retry_attempt     INTEGER NOT NULL DEFAULT 0,
        run_as_user       TEXT NOT NULL DEFAULT '',
        working_directory TEXT NOT NULL DEFAULT '',
        environment       TEXT NOT NULL DEFAULT '',
        app_context       TEXT NOT NULL DEFAULT '',
        environment_snapshot TEXT NOT NULL DEFAULT '',
        pid               INTEGER,
        trigger_type      TEXT NOT NULL DEFAULT 'scheduled'
      )
    ''');

    await _ensureColumn(
      _tableName,
      'collect_app_metadata',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      _tableName,
      'collect_host_metadata',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      _tableName,
      'collect_environment_snapshot',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      _tableName,
      'on_success_severity',
      "TEXT NOT NULL DEFAULT 'success'",
    );
    await _ensureColumn(
      _tableName,
      'on_failure_severity',
      "TEXT NOT NULL DEFAULT 'error'",
    );
    await _ensureColumn(
      _tableName,
      'on_timeout_severity',
      "TEXT NOT NULL DEFAULT 'warning'",
    );
    await _ensureColumn(
      _tableName,
      'on_success_play_sound',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      _tableName,
      'on_failure_play_sound',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      _tableName,
      'on_timeout_play_sound',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      _tableName,
      'on_success_vibrate',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      _tableName,
      'on_failure_vibrate',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      _tableName,
      'on_timeout_vibrate',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      _historyTable,
      'app_context',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      _historyTable,
      'environment_snapshot',
      "TEXT NOT NULL DEFAULT ''",
    );
  }

  // Cron jobs CRUD
  Future<List<CronEntry>> loadAll() async {
    final rows = await _db.query(
      _tableName,
      orderBy: 'sort_order ASC, rowid ASC',
    );
    final entries = <CronEntry>[];
    for (final row in rows) {
      try {
        entries.add(
          CronEntry(
            id: '${row['id']}'.trim(),
            name: '${row['name'] ?? ''}'.trim(),
            description: '${row['description'] ?? ''}'.trim(),
            scriptType:
                CronScriptType.fromStorage('${row['script_type'] ?? ''}') ??
                CronScriptType.command,
            scriptPath: nullIfBlank('${row['script_path'] ?? ''}'),
            scriptContent: nullIfBlank('${row['script_content'] ?? ''}'),
            cronExpression: '${row['cron_expression'] ?? '* * * * *'}'.trim(),
            retryCount: (row['retry_count'] as int?) ?? kCronDefaultRetryCount,
            timeoutSeconds:
                (row['timeout_seconds'] as int?) ?? kCronDefaultTimeoutSeconds,
            runAsUser: nullIfBlank('${row['run_as_user'] ?? ''}'),
            tags: _parseTags('${row['tags'] ?? ''}'),
            enabled: boolFromValue(row['enabled']),
            status: CronJobStatus.fromStorage('${row['status'] ?? ''}'),
            onSuccessNotify: CronNotifyType.fromStorage(
              '${row['on_success_notify'] ?? ''}',
            ),
            onFailureNotify: CronNotifyType.fromStorage(
              '${row['on_failure_notify'] ?? ''}',
            ),
            onTimeoutNotify: CronNotifyType.fromStorage(
              '${row['on_timeout_notify'] ?? ''}',
            ),
            onSuccessSeverity: CronNotifySeverity.fromStorage(
              '${row['on_success_severity'] ?? ''}',
              fallback: CronNotifySeverity.success,
            ),
            onFailureSeverity: CronNotifySeverity.fromStorage(
              '${row['on_failure_severity'] ?? ''}',
              fallback: CronNotifySeverity.error,
            ),
            onTimeoutSeverity: CronNotifySeverity.fromStorage(
              '${row['on_timeout_severity'] ?? ''}',
              fallback: CronNotifySeverity.warning,
            ),
            onSuccessPlaySound: boolFromValue(row['on_success_play_sound']),
            onFailurePlaySound: boolFromValue(
              row['on_failure_play_sound'],
              defaultValue: true,
            ),
            onTimeoutPlaySound: boolFromValue(
              row['on_timeout_play_sound'],
              defaultValue: true,
            ),
            onSuccessVibrate: boolFromValue(row['on_success_vibrate']),
            onFailureVibrate: boolFromValue(
              row['on_failure_vibrate'],
              defaultValue: true,
            ),
            onTimeoutVibrate: boolFromValue(
              row['on_timeout_vibrate'],
              defaultValue: true,
            ),
            onSuccessMessage: nullIfBlank('${row['on_success_message'] ?? ''}'),
            onFailureMessage: nullIfBlank('${row['on_failure_message'] ?? ''}'),
            onTimeoutMessage: nullIfBlank('${row['on_timeout_message'] ?? ''}'),
            collectAppMetadata: boolFromValue(
              row['collect_app_metadata'],
              defaultValue: true,
            ),
            collectHostMetadata: boolFromValue(
              row['collect_host_metadata'],
              defaultValue: true,
            ),
            collectEnvironmentSnapshot: boolFromValue(
              row['collect_environment_snapshot'],
            ),
            workingDirectory: nullIfBlank('${row['working_directory'] ?? ''}'),
            environment: _parseEnv('${row['environment'] ?? ''}'),
            maxRetryDelaySeconds:
                (row['max_retry_delay_seconds'] as int?) ??
                kCronDefaultRetryDelaySeconds,
            lastRunAt: _parseDateTime(row['last_run_at']),
            nextRunAt: _parseDateTime(row['next_run_at']),
            lastExitCode: row['last_exit_code'] as int?,
            consecutiveFailures: (row['consecutive_failures'] as int?) ?? 0,
            createdAt: _parseDateTime(row['created_at']),
            updatedAt: _parseDateTime(row['updated_at']),
          ),
        );
      } catch (error, stack) {
        silentLog(
          'crons_store',
          'skipped malformed cron row id=${row['id']}',
          error,
          stack,
        );
      }
    }
    return entries;
  }

  Future<void> saveAll(List<CronEntry> entries) async {
    final batch = _db.batch();
    batch.delete(_tableName);
    for (var i = 0; i < entries.length; i++) {
      batch.insert(_tableName, _entryToRow(entries[i], sortOrder: i));
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateOne(CronEntry entry) async {
    final updated = await _db.update(
      _tableName,
      _entryToRow(entry),
      where: 'id = ?',
      whereArgs: <Object?>[entry.id],
    );
    if (updated != 1) {
      throw StateError('Cron no longer exists: ${entry.id}');
    }
  }

  Map<String, Object?> _entryToRow(CronEntry entry, {int? sortOrder}) {
    return <String, Object?>{
      'id': entry.id,
      'name': entry.name,
      'description': entry.description,
      'script_type': entry.scriptType.storageValue,
      'script_path': entry.scriptPath ?? '',
      'script_content': entry.scriptContent ?? '',
      'cron_expression': entry.cronExpression,
      'retry_count': entry.retryCount,
      'timeout_seconds': entry.timeoutSeconds,
      'run_as_user': entry.runAsUser ?? '',
      'tags': entry.tags.join(','),
      'enabled': entry.enabled ? 1 : 0,
      'status': entry.status.storageValue,
      'on_success_notify': entry.onSuccessNotify.storageValue,
      'on_failure_notify': entry.onFailureNotify.storageValue,
      'on_timeout_notify': entry.onTimeoutNotify.storageValue,
      'on_success_severity': entry.onSuccessSeverity.storageValue,
      'on_failure_severity': entry.onFailureSeverity.storageValue,
      'on_timeout_severity': entry.onTimeoutSeverity.storageValue,
      'on_success_play_sound': entry.onSuccessPlaySound ? 1 : 0,
      'on_failure_play_sound': entry.onFailurePlaySound ? 1 : 0,
      'on_timeout_play_sound': entry.onTimeoutPlaySound ? 1 : 0,
      'on_success_vibrate': entry.onSuccessVibrate ? 1 : 0,
      'on_failure_vibrate': entry.onFailureVibrate ? 1 : 0,
      'on_timeout_vibrate': entry.onTimeoutVibrate ? 1 : 0,
      'on_success_message': entry.onSuccessMessage ?? '',
      'on_failure_message': entry.onFailureMessage ?? '',
      'on_timeout_message': entry.onTimeoutMessage ?? '',
      'collect_app_metadata': entry.collectAppMetadata ? 1 : 0,
      'collect_host_metadata': entry.collectHostMetadata ? 1 : 0,
      'collect_environment_snapshot': entry.collectEnvironmentSnapshot ? 1 : 0,
      'working_directory': entry.workingDirectory ?? '',
      'environment': entry.environment.entries
          .map((en) => '${en.key}=${en.value}')
          .join('\n'),
      'max_retry_delay_seconds': entry.maxRetryDelaySeconds,
      'last_run_at': entry.lastRunAt?.toIso8601String() ?? '',
      'next_run_at': entry.nextRunAt?.toIso8601String() ?? '',
      'last_exit_code': entry.lastExitCode,
      'consecutive_failures': entry.consecutiveFailures,
      'created_at': entry.createdAt?.toIso8601String() ?? '',
      'updated_at': entry.updatedAt?.toIso8601String() ?? '',
      if (sortOrder != null) 'sort_order': sortOrder,
    };
  }

  Future<void> delete(String id) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  // Execution history
  Future<void> insertHistory(CronExecutionRecord record) async {
    await _db.insert(_historyTable, <String, Object?>{
      'id': record.id,
      'cron_id': record.cronId,
      'started_at': record.startedAt.toIso8601String(),
      'finished_at': record.finishedAt?.toIso8601String() ?? '',
      'status': record.status,
      'exit_code': record.exitCode,
      'stdout': record.stdout,
      'stderr': record.stderr,
      'error_message': record.errorMessage ?? '',
      'elapsed_ms': record.elapsedMs,
      'retry_attempt': record.retryAttempt,
      'run_as_user': record.runAsUser ?? '',
      'working_directory': record.workingDirectory ?? '',
      'environment': record.environment.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n'),
      'app_context': record.appContext.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n'),
      'environment_snapshot': record.environmentSnapshot.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n'),
      'pid': record.pid,
      'trigger_type': record.triggerType,
    });
  }

  Future<List<CronExecutionRecord>> loadHistory(
    String cronId, {
    int limit = 50,
  }) async {
    final rows = await _db.query(
      _historyTable,
      where: 'cron_id = ?',
      whereArgs: <Object?>[cronId],
      orderBy: 'started_at DESC',
      limit: limit,
    );
    final records = <CronExecutionRecord>[];
    for (final row in rows) {
      try {
        records.add(
          CronExecutionRecord(
            id: '${row['id']}'.trim(),
            cronId: '${row['cron_id']}'.trim(),
            startedAt: _parseDateTime(row['started_at']) ?? DateTime.now(),
            finishedAt: _parseDateTime(row['finished_at']),
            status: '${row['status'] ?? 'unknown'}'.trim(),
            exitCode: row['exit_code'] as int?,
            stdout: '${row['stdout'] ?? ''}'.trim(),
            stderr: '${row['stderr'] ?? ''}'.trim(),
            errorMessage: nullIfBlank('${row['error_message'] ?? ''}'),
            elapsedMs: (row['elapsed_ms'] as int?) ?? 0,
            retryAttempt: (row['retry_attempt'] as int?) ?? 0,
            runAsUser: nullIfBlank('${row['run_as_user'] ?? ''}'),
            workingDirectory: nullIfBlank('${row['working_directory'] ?? ''}'),
            environment: _parseEnv('${row['environment'] ?? ''}'),
            appContext: _parseEnv('${row['app_context'] ?? ''}'),
            environmentSnapshot: _parseEnv(
              '${row['environment_snapshot'] ?? ''}',
            ),
            pid: row['pid'] as int?,
            triggerType: '${row['trigger_type'] ?? 'scheduled'}'.trim(),
          ),
        );
      } catch (error, stack) {
        silentLog(
          'crons_store',
          'skipped malformed history row id=${row['id']}',
          error,
          stack,
        );
      }
    }
    return records;
  }

  Future<void> deleteHistoryForCron(String cronId) async {
    await _db.delete(
      _historyTable,
      where: 'cron_id = ?',
      whereArgs: <Object?>[cronId],
    );
  }

  Future<void> deleteHistoryRecord(String recordId) async {
    await _db.delete(
      _historyTable,
      where: 'id = ?',
      whereArgs: <Object?>[recordId],
    );
  }

  /// 删除所有 [cutoff] 之前的历史记录，返回受影响行数。
  /// 用于冷启动时的自动清理 worker。
  /// 注意：started_at 列存的是 ISO8601 字符串，字典序与时间序一致，
  /// 因此可直接用字符串比较，无需 datetime() 函数。
  Future<int> deleteHistoryOlderThan(DateTime cutoff) async {
    return _db.delete(
      _historyTable,
      where: 'started_at < ?',
      whereArgs: <Object?>[cutoff.toIso8601String()],
    );
  }

  /// 清空全部 cron 执行历史记录。返回受影响行数。
  /// 仅由全局设置中的"日志清理 / 全部数据清空"使用；调用方负责同步刷新
  /// 内存缓存。
  Future<int> deleteAllHistory() async {
    return _db.delete(_historyTable);
  }

  /// 估算 cron 执行历史在数据库中占用的近似字节数。
  /// 仅汇总主要 TEXT 列（stdout/stderr/cron_id/started_at），用于"日志清理"
  /// 设置面板的人类友好大小展示。
  Future<({int rowCount, int approxBytes})> historyApproxSize() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS cnt, '
      'COALESCE(SUM(LENGTH(IFNULL(stdout, \'\')) '
      '+ LENGTH(IFNULL(stderr, \'\')) '
      '+ LENGTH(IFNULL(cron_id, \'\')) '
      '+ LENGTH(IFNULL(started_at, \'\'))), 0) AS bytes '
      'FROM $_historyTable',
    );
    if (rows.isEmpty) {
      return (rowCount: 0, approxBytes: 0);
    }
    final row = rows.first;
    final cnt = (row['cnt'] as int?) ?? 0;
    final bytes = (row['bytes'] as int?) ?? 0;
    return (rowCount: cnt, approxBytes: bytes);
  }

  Future<void> pruneHistory(String cronId, {int keep = 100}) async {
    final rows = await _db.query(
      _historyTable,
      columns: ['id'],
      where: 'cron_id = ?',
      whereArgs: <Object?>[cronId],
      orderBy: 'started_at DESC',
      limit: 1,
      offset: keep,
    );
    if (rows.isEmpty) return;
    await _db.rawDelete(
      '''
      DELETE FROM $_historyTable
      WHERE cron_id = ? AND started_at < (
        SELECT started_at FROM $_historyTable
        WHERE cron_id = ?
        ORDER BY started_at DESC
        LIMIT 1 OFFSET ?
      )
    ''',
      [cronId, cronId, keep],
    );
  }

  Future<void> _ensureColumn(
    String table,
    String column,
    String definition,
  ) async {
    final rows = await _db.rawQuery('PRAGMA table_info($table)');
    final exists = rows.any((row) => '${row['name']}' == column);
    if (exists) return;
    await _db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}

// Helpers
List<String> _parseTags(String raw) {
  return splitTrimmedNonEmpty(raw);
}

Map<String, String> _parseEnv(String raw) {
  return keyValueMapFromValue(raw);
}

DateTime? _parseDateTime(Object? raw) {
  return dateTimeFromValue(raw);
}
