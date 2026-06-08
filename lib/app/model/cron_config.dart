import '../../shared/util/input_value_parsing.dart';

/// Type of script source for a cron job.
enum CronScriptType {
  command('command', 'Command', '命令'),
  script('script', 'Script', '脚本'),
  // 2026-04-25 system-managed Agent entries (Hermes Talker self-learning).
  // These dispatch to an in-process agent handler rather than spawning a
  // shell process. UI must render them read-only with a lock icon.
  agent('agent', 'Agent', 'Agent');

  const CronScriptType(this.storageValue, this.labelEn, this.labelZh);

  final String storageValue;
  final String labelEn;
  final String labelZh;

  String label(bool isZh) => isZh ? labelZh : labelEn;

  static CronScriptType? fromStorage(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final t in values) {
      if (t.storageValue == value) return t;
    }
    return null;
  }
}

/// Runtime status of a cron job.
enum CronJobStatus {
  running('running', 'Running', '运行中'),
  paused('paused', 'Paused', '已暂停'),
  failed('failed', 'Failed', '失败'),
  error('error', 'Error', '异常'),
  idle('idle', 'Idle', '空闲');

  const CronJobStatus(this.storageValue, this.labelEn, this.labelZh);

  final String storageValue;
  final String labelEn;
  final String labelZh;

  String label(bool isZh) => isZh ? labelZh : labelEn;

  static CronJobStatus fromStorage(String? value) {
    if (value == null || value.isEmpty) return CronJobStatus.idle;
    for (final s in values) {
      if (s.storageValue == value) return s;
    }
    return CronJobStatus.idle;
  }
}

/// Notification type for cron job events.
enum CronNotifyType {
  none('none', 'None', '无'),
  log('log', 'Log Only', '仅日志'),
  system('system', 'System Notification', '系统通知'),
  appNotification('app_notification', 'In-App Notification', '应用内通知');

  const CronNotifyType(this.storageValue, this.labelEn, this.labelZh);

  final String storageValue;
  final String labelEn;
  final String labelZh;

  String label(bool isZh) => isZh ? labelZh : labelEn;

  static CronNotifyType fromStorage(String? value) {
    if (value == null || value.isEmpty) return CronNotifyType.log;
    for (final n in values) {
      if (n.storageValue == value) return n;
    }
    return CronNotifyType.log;
  }
}

/// Notification severity for cron job events.
enum CronNotifySeverity {
  info('info', 'Info', '信息'),
  success('success', 'Success', '成功'),
  warning('warning', 'Warning', '警告'),
  error('error', 'Error', '错误'),
  critical('critical', 'Critical', '严重');

  const CronNotifySeverity(this.storageValue, this.labelEn, this.labelZh);

  final String storageValue;
  final String labelEn;
  final String labelZh;

  String label(bool isZh) => isZh ? labelZh : labelEn;

  static CronNotifySeverity fromStorage(
    String? value, {
    CronNotifySeverity fallback = CronNotifySeverity.info,
  }) {
    if (value == null || value.isEmpty) return fallback;
    for (final s in values) {
      if (s.storageValue == value) return s;
    }
    return fallback;
  }
}

/// A single cron job entry.
class CronEntry {
  const CronEntry({
    required this.id,
    required this.name,
    this.description = '',
    this.scriptType = CronScriptType.command,
    this.scriptPath,
    this.scriptContent,
    this.cronExpression = '* * * * *',
    this.retryCount = 0,
    this.timeoutSeconds = 60,
    this.runAsUser,
    this.tags = const <String>[],
    this.enabled = true,
    this.status = CronJobStatus.idle,
    this.onSuccessNotify = CronNotifyType.log,
    this.onFailureNotify = CronNotifyType.system,
    this.onTimeoutNotify = CronNotifyType.system,
    this.onSuccessSeverity = CronNotifySeverity.success,
    this.onFailureSeverity = CronNotifySeverity.error,
    this.onTimeoutSeverity = CronNotifySeverity.warning,
    this.onSuccessPlaySound = false,
    this.onFailurePlaySound = true,
    this.onTimeoutPlaySound = true,
    this.onSuccessVibrate = false,
    this.onFailureVibrate = true,
    this.onTimeoutVibrate = true,
    this.onSuccessMessage,
    this.onFailureMessage,
    this.onTimeoutMessage,
    this.collectAppMetadata = true,
    this.collectHostMetadata = true,
    this.collectEnvironmentSnapshot = false,
    this.workingDirectory,
    this.environment = const <String, String>{},
    this.maxRetryDelaySeconds = 30,
    this.lastRunAt,
    this.nextRunAt,
    this.lastExitCode,
    this.consecutiveFailures = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory CronEntry.fromJson(Map<String, Object?> json) {
    return CronEntry(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      description: '${json['description'] ?? ''}'.trim(),
      scriptType:
          CronScriptType.fromStorage('${json['script_type'] ?? ''}') ??
          CronScriptType.command,
      scriptPath: nullIfBlank('${json['script_path'] ?? ''}'),
      scriptContent: nullIfBlank('${json['script_content'] ?? ''}'),
      cronExpression: '${json['cron_expression'] ?? '* * * * *'}'.trim(),
      retryCount: intFromValue(json['retry_count'], fallback: 0),
      timeoutSeconds: intFromValue(json['timeout_seconds'], fallback: 60),
      runAsUser: nullIfBlank('${json['run_as_user'] ?? ''}'),
      tags: stringListFromValue(json['tags']),
      enabled: boolFromValue(json['enabled'], defaultValue: true),
      status: CronJobStatus.fromStorage('${json['status'] ?? ''}'),
      onSuccessNotify: CronNotifyType.fromStorage(
        '${json['on_success_notify'] ?? ''}',
      ),
      onFailureNotify: CronNotifyType.fromStorage(
        '${json['on_failure_notify'] ?? ''}',
      ),
      onTimeoutNotify: CronNotifyType.fromStorage(
        '${json['on_timeout_notify'] ?? ''}',
      ),
      onSuccessSeverity: CronNotifySeverity.fromStorage(
        '${json['on_success_severity'] ?? ''}',
        fallback: CronNotifySeverity.success,
      ),
      onFailureSeverity: CronNotifySeverity.fromStorage(
        '${json['on_failure_severity'] ?? ''}',
        fallback: CronNotifySeverity.error,
      ),
      onTimeoutSeverity: CronNotifySeverity.fromStorage(
        '${json['on_timeout_severity'] ?? ''}',
        fallback: CronNotifySeverity.warning,
      ),
      onSuccessPlaySound: boolFromValue(json['on_success_play_sound']),
      onFailurePlaySound: boolFromValue(
        json['on_failure_play_sound'],
        defaultValue: true,
      ),
      onTimeoutPlaySound: boolFromValue(
        json['on_timeout_play_sound'],
        defaultValue: true,
      ),
      onSuccessVibrate: boolFromValue(json['on_success_vibrate']),
      onFailureVibrate: boolFromValue(
        json['on_failure_vibrate'],
        defaultValue: true,
      ),
      onTimeoutVibrate: boolFromValue(
        json['on_timeout_vibrate'],
        defaultValue: true,
      ),
      onSuccessMessage: nullIfBlank('${json['on_success_message'] ?? ''}'),
      onFailureMessage: nullIfBlank('${json['on_failure_message'] ?? ''}'),
      onTimeoutMessage: nullIfBlank('${json['on_timeout_message'] ?? ''}'),
      collectAppMetadata: boolFromValue(
        json['collect_app_metadata'],
        defaultValue: true,
      ),
      collectHostMetadata: boolFromValue(
        json['collect_host_metadata'],
        defaultValue: true,
      ),
      collectEnvironmentSnapshot: boolFromValue(
        json['collect_environment_snapshot'],
      ),
      workingDirectory: nullIfBlank('${json['working_directory'] ?? ''}'),
      environment: keyValueMapFromValue(json['environment']),
      maxRetryDelaySeconds: intFromValue(
        json['max_retry_delay_seconds'],
        fallback: 30,
      ),
      lastRunAt: dateTimeFromValue(json['last_run_at']),
      nextRunAt: dateTimeFromValue(json['next_run_at']),
      lastExitCode: optionalIntFromValue(json['last_exit_code']),
      consecutiveFailures: intFromValue(
        json['consecutive_failures'],
        fallback: 0,
      ),
      createdAt: dateTimeFromValue(json['created_at']),
      updatedAt: dateTimeFromValue(json['updated_at']),
    );
  }

  final String id;
  final String name;
  final String description;
  final CronScriptType scriptType;
  final String? scriptPath;
  final String? scriptContent;
  final String cronExpression;
  final int retryCount;
  final int timeoutSeconds;
  final String? runAsUser;
  final List<String> tags;
  final bool enabled;
  final CronJobStatus status;
  final CronNotifyType onSuccessNotify;
  final CronNotifyType onFailureNotify;
  final CronNotifyType onTimeoutNotify;
  final CronNotifySeverity onSuccessSeverity;
  final CronNotifySeverity onFailureSeverity;
  final CronNotifySeverity onTimeoutSeverity;
  final bool onSuccessPlaySound;
  final bool onFailurePlaySound;
  final bool onTimeoutPlaySound;
  final bool onSuccessVibrate;
  final bool onFailureVibrate;
  final bool onTimeoutVibrate;
  final String? onSuccessMessage;
  final String? onFailureMessage;
  final String? onTimeoutMessage;
  final bool collectAppMetadata;
  final bool collectHostMetadata;
  final bool collectEnvironmentSnapshot;
  final String? workingDirectory;
  final Map<String, String> environment;
  final int maxRetryDelaySeconds;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final int? lastExitCode;
  final int consecutiveFailures;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasScript =>
      (scriptPath != null && scriptPath!.isNotEmpty) ||
      (scriptContent != null && scriptContent!.isNotEmpty);

  /// Human-readable cron schedule description.
  String scheduleLabel(bool isZh) {
    final parts = cronExpression.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) {
      return isZh ? '无效表达式' : 'Invalid expression';
    }
    if (parts.every((p) => p == '*')) {
      return isZh ? '每分钟' : 'Every minute';
    }
    return cronExpression;
  }

  CronEntry copyWith({
    String? id,
    String? name,
    String? description,
    CronScriptType? scriptType,
    String? scriptPath,
    String? scriptContent,
    String? cronExpression,
    int? retryCount,
    int? timeoutSeconds,
    String? runAsUser,
    List<String>? tags,
    bool? enabled,
    CronJobStatus? status,
    CronNotifyType? onSuccessNotify,
    CronNotifyType? onFailureNotify,
    CronNotifyType? onTimeoutNotify,
    CronNotifySeverity? onSuccessSeverity,
    CronNotifySeverity? onFailureSeverity,
    CronNotifySeverity? onTimeoutSeverity,
    bool? onSuccessPlaySound,
    bool? onFailurePlaySound,
    bool? onTimeoutPlaySound,
    bool? onSuccessVibrate,
    bool? onFailureVibrate,
    bool? onTimeoutVibrate,
    String? onSuccessMessage,
    String? onFailureMessage,
    String? onTimeoutMessage,
    bool? collectAppMetadata,
    bool? collectHostMetadata,
    bool? collectEnvironmentSnapshot,
    String? workingDirectory,
    Map<String, String>? environment,
    int? maxRetryDelaySeconds,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    int? lastExitCode,
    int? consecutiveFailures,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearScriptPath = false,
    bool clearScriptContent = false,
    bool clearRunAsUser = false,
    bool clearWorkingDirectory = false,
    bool clearLastRunAt = false,
    bool clearNextRunAt = false,
    bool clearLastExitCode = false,
  }) {
    return CronEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      scriptType: scriptType ?? this.scriptType,
      scriptPath: clearScriptPath ? null : (scriptPath ?? this.scriptPath),
      scriptContent: clearScriptContent
          ? null
          : (scriptContent ?? this.scriptContent),
      cronExpression: cronExpression ?? this.cronExpression,
      retryCount: retryCount ?? this.retryCount,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      runAsUser: clearRunAsUser ? null : (runAsUser ?? this.runAsUser),
      tags: tags ?? this.tags,
      enabled: enabled ?? this.enabled,
      status: status ?? this.status,
      onSuccessNotify: onSuccessNotify ?? this.onSuccessNotify,
      onFailureNotify: onFailureNotify ?? this.onFailureNotify,
      onTimeoutNotify: onTimeoutNotify ?? this.onTimeoutNotify,
      onSuccessSeverity: onSuccessSeverity ?? this.onSuccessSeverity,
      onFailureSeverity: onFailureSeverity ?? this.onFailureSeverity,
      onTimeoutSeverity: onTimeoutSeverity ?? this.onTimeoutSeverity,
      onSuccessPlaySound: onSuccessPlaySound ?? this.onSuccessPlaySound,
      onFailurePlaySound: onFailurePlaySound ?? this.onFailurePlaySound,
      onTimeoutPlaySound: onTimeoutPlaySound ?? this.onTimeoutPlaySound,
      onSuccessVibrate: onSuccessVibrate ?? this.onSuccessVibrate,
      onFailureVibrate: onFailureVibrate ?? this.onFailureVibrate,
      onTimeoutVibrate: onTimeoutVibrate ?? this.onTimeoutVibrate,
      onSuccessMessage: onSuccessMessage ?? this.onSuccessMessage,
      onFailureMessage: onFailureMessage ?? this.onFailureMessage,
      onTimeoutMessage: onTimeoutMessage ?? this.onTimeoutMessage,
      collectAppMetadata: collectAppMetadata ?? this.collectAppMetadata,
      collectHostMetadata: collectHostMetadata ?? this.collectHostMetadata,
      collectEnvironmentSnapshot:
          collectEnvironmentSnapshot ?? this.collectEnvironmentSnapshot,
      workingDirectory: clearWorkingDirectory
          ? null
          : (workingDirectory ?? this.workingDirectory),
      environment: environment ?? this.environment,
      maxRetryDelaySeconds: maxRetryDelaySeconds ?? this.maxRetryDelaySeconds,
      lastRunAt: clearLastRunAt ? null : (lastRunAt ?? this.lastRunAt),
      nextRunAt: clearNextRunAt ? null : (nextRunAt ?? this.nextRunAt),
      lastExitCode: clearLastExitCode
          ? null
          : (lastExitCode ?? this.lastExitCode),
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'description': description,
      'script_type': scriptType.storageValue,
      'script_path': scriptPath ?? '',
      'script_content': scriptContent ?? '',
      'cron_expression': cronExpression,
      'retry_count': retryCount,
      'timeout_seconds': timeoutSeconds,
      'run_as_user': runAsUser ?? '',
      'tags': tags.join(','),
      'enabled': enabled,
      'status': status.storageValue,
      'on_success_notify': onSuccessNotify.storageValue,
      'on_failure_notify': onFailureNotify.storageValue,
      'on_timeout_notify': onTimeoutNotify.storageValue,
      'on_success_severity': onSuccessSeverity.storageValue,
      'on_failure_severity': onFailureSeverity.storageValue,
      'on_timeout_severity': onTimeoutSeverity.storageValue,
      'on_success_play_sound': onSuccessPlaySound,
      'on_failure_play_sound': onFailurePlaySound,
      'on_timeout_play_sound': onTimeoutPlaySound,
      'on_success_vibrate': onSuccessVibrate,
      'on_failure_vibrate': onFailureVibrate,
      'on_timeout_vibrate': onTimeoutVibrate,
      'on_success_message': onSuccessMessage ?? '',
      'on_failure_message': onFailureMessage ?? '',
      'on_timeout_message': onTimeoutMessage ?? '',
      'collect_app_metadata': collectAppMetadata,
      'collect_host_metadata': collectHostMetadata,
      'collect_environment_snapshot': collectEnvironmentSnapshot,
      'working_directory': workingDirectory ?? '',
      'environment': environment.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n'),
      'max_retry_delay_seconds': maxRetryDelaySeconds,
      'last_run_at': lastRunAt?.toIso8601String() ?? '',
      'next_run_at': nextRunAt?.toIso8601String() ?? '',
      'last_exit_code': lastExitCode,
      'consecutive_failures': consecutiveFailures,
      'created_at': createdAt?.toIso8601String() ?? '',
      'updated_at': updatedAt?.toIso8601String() ?? '',
    };
  }
}

/// A single execution history record for a cron job.
class CronExecutionRecord {
  const CronExecutionRecord({
    required this.id,
    required this.cronId,
    required this.startedAt,
    this.finishedAt,
    required this.status,
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.errorMessage,
    this.elapsedMs = 0,
    this.retryAttempt = 0,
    this.runAsUser,
    this.workingDirectory,
    this.environment = const <String, String>{},
    this.appContext = const <String, String>{},
    this.environmentSnapshot = const <String, String>{},
    this.pid,
    this.triggerType = 'scheduled',
  });

  factory CronExecutionRecord.fromJson(Map<String, Object?> json) {
    return CronExecutionRecord(
      id: '${json['id'] ?? ''}'.trim(),
      cronId: '${json['cron_id'] ?? ''}'.trim(),
      startedAt: dateTimeFromValue(json['started_at']) ?? DateTime.now(),
      finishedAt: dateTimeFromValue(json['finished_at']),
      status: '${json['status'] ?? 'unknown'}'.trim(),
      exitCode: optionalIntFromValue(json['exit_code']),
      stdout: '${json['stdout'] ?? ''}'.trim(),
      stderr: '${json['stderr'] ?? ''}'.trim(),
      errorMessage: nullIfBlank('${json['error_message'] ?? ''}'),
      elapsedMs: intFromValue(json['elapsed_ms'], fallback: 0),
      retryAttempt: intFromValue(json['retry_attempt'], fallback: 0),
      runAsUser: nullIfBlank('${json['run_as_user'] ?? ''}'),
      workingDirectory: nullIfBlank('${json['working_directory'] ?? ''}'),
      environment: keyValueMapFromValue(json['environment']),
      appContext: keyValueMapFromValue(json['app_context']),
      environmentSnapshot: keyValueMapFromValue(json['environment_snapshot']),
      pid: optionalIntFromValue(json['pid']),
      triggerType: '${json['trigger_type'] ?? 'scheduled'}'.trim(),
    );
  }

  final String id;
  final String cronId;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// One of: 'success', 'failed', 'timed_out', 'running', 'killed'.
  final String status;
  final int? exitCode;
  final String stdout;
  final String stderr;
  final String? errorMessage;
  final int elapsedMs;
  final int retryAttempt;
  final String? runAsUser;
  final String? workingDirectory;

  /// Script-level environment overrides configured on the cron entry.
  final Map<String, String> environment;

  /// Captured app / host runtime context at execution time.
  final Map<String, String> appContext;

  /// Captured effective process environment snapshot at execution time.
  final Map<String, String> environmentSnapshot;

  final int? pid;

  /// One of: 'scheduled', 'manual'.
  final String triggerType;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'cron_id': cronId,
      'started_at': startedAt.toIso8601String(),
      'finished_at': finishedAt?.toIso8601String() ?? '',
      'status': status,
      'exit_code': exitCode,
      'stdout': stdout,
      'stderr': stderr,
      'error_message': errorMessage ?? '',
      'elapsed_ms': elapsedMs,
      'retry_attempt': retryAttempt,
      'run_as_user': runAsUser ?? '',
      'working_directory': workingDirectory ?? '',
      'environment': environment.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n'),
      'app_context': appContext.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n'),
      'environment_snapshot': environmentSnapshot.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n'),
      'pid': pid,
      'trigger_type': triggerType,
    };
  }
}
