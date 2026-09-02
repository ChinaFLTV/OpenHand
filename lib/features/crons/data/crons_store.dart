import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/model/cron_config.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../model/cron_parser.dart';

/// 基于 SQLite 的定时任务与执行历史存储。
class CronsStore {
  CronsStore({this._database});

  static const String _tableName = 'cron_jobs';
  static const String _historyTable = 'cron_execution_history';
  static const int _maxStoredCounter = 0x7fffffff;
  static const List<String> _entryTextColumns = <String>[
    'id',
    'name',
    'description',
    'script_type',
    'script_path',
    'script_content',
    'cron_expression',
    'run_as_user',
    'tags',
    'status',
    'on_success_notify',
    'on_failure_notify',
    'on_timeout_notify',
    'on_success_severity',
    'on_failure_severity',
    'on_timeout_severity',
    'on_success_message',
    'on_failure_message',
    'on_timeout_message',
    'working_directory',
    'environment',
    'last_run_at',
    'next_run_at',
    'created_at',
    'updated_at',
  ];
  static const Set<String> _historyStatuses = <String>{
    'success',
    'failed',
    'timed_out',
    'running',
    'killed',
  };

  final Database? _database;
  late final OpenHandRetryableAsyncCache<void> _tableInitialization =
      OpenHandRetryableAsyncCache<void>(_ensureTables);

  Database get _db => _database ?? DatabaseService.instance.database;

  /// 确保任务表和历史表就绪，并合并并发初始化。
  Future<void> ensureTable() => _tableInitialization.load();

  Future<void> _ensureTables() async {
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
    await _db.update(
      _tableName,
      <String, Object?>{'script_type': CronScriptType.managed.storageValue},
      where: 'script_type = ?',
      whereArgs: <Object?>[CronScriptType.legacyManagedStorageValue],
    );
  }

  // 定时任务读写。
  Future<List<CronEntry>> loadAll() async {
    await _validateStoredEntryScale();
    final rows = await _db.query(
      _tableName,
      orderBy: 'sort_order ASC, rowid ASC',
      limit: kCronMaxEntryCount + 1,
    );
    if (rows.length > kCronMaxEntryCount) {
      throw const FormatException('定时任务数量超过安全上限。');
    }
    final entries = <CronEntry>[];
    final seenIds = <String>{};
    var totalPayloadBytes = 0;
    for (final row in rows) {
      final payloadBytes = _entryPayloadBytes(row);
      totalPayloadBytes += payloadBytes;
      if (payloadBytes > kCronMaxEntryPayloadBytes ||
          totalPayloadBytes > kCronMaxTotalPayloadBytes) {
        throw const FormatException('定时任务存储规模超过安全上限。');
      }
      final entry = _rowToEntry(row);
      if (!seenIds.add(entry.id)) {
        throw FormatException('定时任务 ID 重复：${entry.id}');
      }
      entries.add(entry);
    }
    return entries;
  }

  CronEntry _rowToEntry(Map<String, Object?> row) {
    final id = _canonicalText(row, 'id');
    final name = _canonicalText(row, 'name');
    final cronExpression = _canonicalText(row, 'cron_expression');
    if (id.isEmpty || name.isEmpty || !CronParser.isValid(cronExpression)) {
      throw FormatException('定时任务记录无效：$id');
    }
    final tagsText = _text(row, 'tags');
    final tags = _parseTags(tagsText);
    final environmentText = _text(row, 'environment');
    final environment = _parseEnv(environmentText);
    if (tags.join(',') != tagsText ||
        _encodeEnv(environment) != environmentText) {
      throw FormatException('定时任务元数据无效：$id');
    }
    _intInRange(row, 'sort_order', 0, _maxStoredCounter);
    return CronEntry(
      id: id,
      name: name,
      description: _text(row, 'description'),
      scriptType: _scriptType(row),
      scriptPath: _optionalText(row, 'script_path'),
      scriptContent: _optionalText(row, 'script_content'),
      cronExpression: cronExpression,
      retryCount: _intInRange(
        row,
        'retry_count',
        kCronMinRetryCount,
        kCronMaxRetryCount,
      ),
      timeoutSeconds: _intInRange(
        row,
        'timeout_seconds',
        kCronMinTimeoutSeconds,
        kCronMaxTimeoutSeconds,
      ),
      runAsUser: _optionalText(row, 'run_as_user'),
      tags: tags,
      enabled: _bool(row, 'enabled'),
      status: _enumValue(
        row,
        'status',
        CronJobStatus.values,
        (value) => value.storageValue,
      ),
      onSuccessNotify: _notifyType(row, 'on_success_notify'),
      onFailureNotify: _notifyType(row, 'on_failure_notify'),
      onTimeoutNotify: _notifyType(row, 'on_timeout_notify'),
      onSuccessSeverity: _severity(row, 'on_success_severity'),
      onFailureSeverity: _severity(row, 'on_failure_severity'),
      onTimeoutSeverity: _severity(row, 'on_timeout_severity'),
      onSuccessPlaySound: _bool(row, 'on_success_play_sound'),
      onFailurePlaySound: _bool(row, 'on_failure_play_sound'),
      onTimeoutPlaySound: _bool(row, 'on_timeout_play_sound'),
      onSuccessVibrate: _bool(row, 'on_success_vibrate'),
      onFailureVibrate: _bool(row, 'on_failure_vibrate'),
      onTimeoutVibrate: _bool(row, 'on_timeout_vibrate'),
      onSuccessMessage: _optionalText(row, 'on_success_message'),
      onFailureMessage: _optionalText(row, 'on_failure_message'),
      onTimeoutMessage: _optionalText(row, 'on_timeout_message'),
      collectAppMetadata: _bool(row, 'collect_app_metadata'),
      collectHostMetadata: _bool(row, 'collect_host_metadata'),
      collectEnvironmentSnapshot: _bool(row, 'collect_environment_snapshot'),
      workingDirectory: _optionalText(row, 'working_directory'),
      environment: environment,
      maxRetryDelaySeconds: _intInRange(
        row,
        'max_retry_delay_seconds',
        kCronMinRetryDelaySeconds,
        kCronMaxRetryDelaySeconds,
      ),
      lastRunAt: _dateTime(row, 'last_run_at'),
      nextRunAt: _dateTime(row, 'next_run_at'),
      lastExitCode: _optionalInt(row, 'last_exit_code'),
      consecutiveFailures: _intInRange(
        row,
        'consecutive_failures',
        0,
        _maxStoredCounter,
      ),
      createdAt: _dateTime(row, 'created_at'),
      updatedAt: _dateTime(row, 'updated_at'),
    );
  }

  String _text(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is String) return value;
    throw FormatException('定时任务字段 $key 必须是文本。');
  }

  String _canonicalText(Map<String, Object?> row, String key) {
    final value = _text(row, key);
    if (value != value.trim()) {
      throw FormatException('定时任务字段 $key 格式不规范。');
    }
    return value;
  }

  String? _optionalText(Map<String, Object?> row, String key) {
    final value = _text(row, key);
    return value.isEmpty ? null : value;
  }

  bool _bool(Map<String, Object?> row, String key) {
    return switch (row[key]) {
      0 => false,
      1 => true,
      _ => throw FormatException('定时任务字段 $key 必须是 0 或 1。'),
    };
  }

  int _intInRange(
    Map<String, Object?> row,
    String key,
    int minimum,
    int maximum,
  ) {
    final value = row[key];
    if (value is! int || value < minimum || value > maximum) {
      throw FormatException('定时任务字段 $key 超出范围。');
    }
    return value;
  }

  int? _optionalInt(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value == null || value is int) return value as int?;
    throw FormatException('定时任务字段 $key 必须是整数。');
  }

  DateTime? _dateTime(Map<String, Object?> row, String key) {
    final raw = _text(row, key);
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || parsed.toIso8601String() != raw) {
      throw FormatException('定时任务字段 $key 无效。');
    }
    return parsed;
  }

  T _enumValue<T extends Enum>(
    Map<String, Object?> row,
    String key,
    Iterable<T> values,
    String Function(T value) storageValue,
  ) {
    final value = enumByStorageValue(values, _text(row, key), storageValue);
    if (value == null) {
      throw FormatException('定时任务字段 $key 包含未知值。');
    }
    return value;
  }

  CronScriptType _scriptType(Map<String, Object?> row) {
    final value = CronScriptType.fromStorage(_text(row, 'script_type'));
    if (value == null) {
      throw const FormatException('定时任务字段 script_type 包含未知值。');
    }
    return value;
  }

  CronNotifyType _notifyType(Map<String, Object?> row, String key) {
    return _enumValue(
      row,
      key,
      CronNotifyType.values,
      (value) => value.storageValue,
    );
  }

  CronNotifySeverity _severity(Map<String, Object?> row, String key) {
    return _enumValue(
      row,
      key,
      CronNotifySeverity.values,
      (value) => value.storageValue,
    );
  }

  Future<void> saveAll(List<CronEntry> entries) async {
    if (entries.length > kCronMaxEntryCount) {
      throw const FormatException('定时任务数量超过安全上限。');
    }
    final rows = <Map<String, Object?>>[];
    final seenIds = <String>{};
    var totalPayloadBytes = 0;
    for (var index = 0; index < entries.length; index++) {
      final row = _entryToRow(entries[index], sortOrder: index);
      final validated = _rowToEntry(row);
      if (!seenIds.add(validated.id)) {
        throw FormatException('定时任务 ID 重复：${validated.id}');
      }
      final payloadBytes = _entryPayloadBytes(row);
      if (payloadBytes > kCronMaxEntryPayloadBytes) {
        throw FormatException('定时任务“${validated.name}”超过单项存储安全上限。');
      }
      totalPayloadBytes += payloadBytes;
      if (totalPayloadBytes > kCronMaxTotalPayloadBytes) {
        throw const FormatException('定时任务总载荷超过存储安全上限。');
      }
      rows.add(row);
    }
    final batch = _db.batch();
    batch.delete(_tableName);
    for (final row in rows) {
      batch.insert(_tableName, row);
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateRuntimeState(CronEntry entry) async {
    if (entry.id.trim() != entry.id ||
        entry.id.isEmpty ||
        entry.consecutiveFailures < 0) {
      throw const FormatException('定时任务运行状态无效。');
    }
    final updated = await _db.update(
      _tableName,
      <String, Object?>{
        'status': entry.status.storageValue,
        'last_run_at': entry.lastRunAt?.toIso8601String() ?? '',
        'next_run_at': entry.nextRunAt?.toIso8601String() ?? '',
        'last_exit_code': entry.lastExitCode,
        'consecutive_failures': entry.consecutiveFailures,
        'updated_at': entry.updatedAt?.toIso8601String() ?? '',
      },
      where: 'id = ?',
      whereArgs: <Object?>[entry.id],
    );
    if (updated != 1) {
      throw StateError('定时任务已不存在：${entry.id}');
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
      'environment': _encodeEnv(entry.environment),
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

  // 执行历史。
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
    if (limit < 1 || limit > kCronMaxHistoryPageSize) {
      throw RangeError.range(limit, 1, kCronMaxHistoryPageSize, 'limit');
    }
    final rows = await _db.query(
      _historyTable,
      where: 'cron_id = ?',
      whereArgs: <Object?>[cronId],
      orderBy: 'started_at DESC',
      limit: limit,
    );
    final records = <CronExecutionRecord>[];
    for (final row in rows) {
      records.add(_historyRowToRecord(row));
    }
    return records;
  }

  CronExecutionRecord _historyRowToRecord(Map<String, Object?> row) {
    final id = _canonicalText(row, 'id');
    final cronId = _canonicalText(row, 'cron_id');
    final status = _canonicalText(row, 'status');
    final triggerType = _canonicalText(row, 'trigger_type');
    if (id.isEmpty ||
        cronId.isEmpty ||
        !_historyStatuses.contains(status) ||
        triggerType.isEmpty) {
      throw FormatException('定时任务历史记录无效：$id');
    }
    final environment = _historyEnvironment(row, 'environment');
    final appContext = _historyEnvironment(row, 'app_context');
    final environmentSnapshot = _historyEnvironment(
      row,
      'environment_snapshot',
    );
    return CronExecutionRecord(
      id: id,
      cronId: cronId,
      startedAt: _requiredDateTime(row, 'started_at'),
      finishedAt: _dateTime(row, 'finished_at'),
      status: status,
      exitCode: _optionalInt(row, 'exit_code'),
      stdout: _text(row, 'stdout'),
      stderr: _text(row, 'stderr'),
      errorMessage: _optionalText(row, 'error_message'),
      elapsedMs: _intInRange(row, 'elapsed_ms', 0, _maxStoredCounter),
      retryAttempt: _intInRange(row, 'retry_attempt', 0, _maxStoredCounter),
      runAsUser: _optionalText(row, 'run_as_user'),
      workingDirectory: _optionalText(row, 'working_directory'),
      environment: environment,
      appContext: appContext,
      environmentSnapshot: environmentSnapshot,
      pid: _optionalInt(row, 'pid'),
      triggerType: triggerType,
    );
  }

  Map<String, String> _historyEnvironment(
    Map<String, Object?> row,
    String key,
  ) {
    final raw = _text(row, key);
    final parsed = _parseEnv(raw);
    if (_encodeEnv(parsed) != raw) {
      throw FormatException('定时任务历史字段 $key 无效。');
    }
    return parsed;
  }

  DateTime _requiredDateTime(Map<String, Object?> row, String key) {
    final value = _dateTime(row, key);
    if (value == null) {
      throw FormatException('定时任务历史字段 $key 不能为空。');
    }
    return value;
  }

  Future<void> deleteHistoryForCron(String cronId) async {
    await _db.delete(
      _historyTable,
      where: 'cron_id = ?',
      whereArgs: <Object?>[cronId],
    );
  }

  Future<bool> deleteHistoryRecord(String cronId, String recordId) async {
    final deleted = await _db.delete(
      _historyTable,
      where: 'cron_id = ? AND id = ?',
      whereArgs: <Object?>[cronId, recordId],
    );
    return deleted == 1;
  }

  /// 删除所有 [cutoff] 之前的历史记录，返回受影响行数。
  /// 用于冷启动时的自动清理任务。
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

  Future<void> _validateStoredEntryScale() async {
    final payloadExpression = _entryTextColumns
        .map((column) => 'COALESCE(LENGTH(CAST($column AS BLOB)), 0)')
        .join(' + ');
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS entry_count,
             COALESCE(MAX($payloadExpression), 0) AS max_entry_bytes,
             COALESCE(SUM($payloadExpression), 0) AS total_payload_bytes
      FROM $_tableName
    ''');
    final row = rows.firstOrNull;
    final entryCount = optionalIntegralIntFromValue(row?['entry_count']);
    final maxEntryBytes = optionalIntegralIntFromValue(row?['max_entry_bytes']);
    final totalPayloadBytes = optionalIntegralIntFromValue(
      row?['total_payload_bytes'],
    );
    if (entryCount == null ||
        maxEntryBytes == null ||
        totalPayloadBytes == null) {
      throw const FormatException('定时任务存储统计无效。');
    }
    if (entryCount > kCronMaxEntryCount ||
        maxEntryBytes > kCronMaxEntryPayloadBytes ||
        totalPayloadBytes > kCronMaxTotalPayloadBytes) {
      throw const FormatException('定时任务存储规模超过安全上限。');
    }
  }

  int _entryPayloadBytes(Map<String, Object?> row) {
    return _entryTextColumns.fold<int>(
      0,
      (total, column) => total + utf8ByteLength('${row[column] ?? ''}'),
    );
  }
}

List<String> _parseTags(String raw) {
  return splitTrimmedNonEmpty(raw);
}

Map<String, String> _parseEnv(String raw) {
  return keyValueMapFromValue(raw);
}

String _encodeEnv(Map<String, String> environment) {
  return environment.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join('\n');
}
