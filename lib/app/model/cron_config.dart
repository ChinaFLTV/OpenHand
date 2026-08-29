import '../../l10n/app_localizations.dart';
import '../../shared/util/input_value_parsing.dart';

const int kCronDefaultRetryCount = 0;
const int kCronMinRetryCount = 0;
const int kCronMaxRetryCount = 10;
const int kCronDefaultTimeoutSeconds = 60;
const int kCronMinTimeoutSeconds = 1;
const int kCronMaxTimeoutSeconds = 3600;
const int kCronDefaultRetryDelaySeconds = 30;
const int kCronMinRetryDelaySeconds = 1;
const int kCronMaxRetryDelaySeconds = 300;
const IntValueRange _cronRetryCountRange = IntValueRange(
  fallback: kCronDefaultRetryCount,
  min: kCronMinRetryCount,
  max: kCronMaxRetryCount,
);
const IntValueRange _cronTimeoutSecondsRange = IntValueRange(
  fallback: kCronDefaultTimeoutSeconds,
  min: kCronMinTimeoutSeconds,
  max: kCronMaxTimeoutSeconds,
);
const IntValueRange _cronRetryDelaySecondsRange = IntValueRange(
  fallback: kCronDefaultRetryDelaySeconds,
  min: kCronMinRetryDelaySeconds,
  max: kCronMaxRetryDelaySeconds,
);

int clampCronRetryCount(int value) {
  return _cronRetryCountRange.normalize(value);
}

int clampCronTimeoutSeconds(int value) {
  return _cronTimeoutSecondsRange.normalize(value);
}

int clampCronRetryDelaySeconds(int value) {
  return _cronRetryDelaySecondsRange.normalize(value);
}

/// 定时任务脚本来源类型。
enum CronScriptType {
  command('command'),
  script('script'),
  // 系统托管任务由进程内处理器执行，界面以只读锁定状态展示。
  managed('managed');

  const CronScriptType(this.storageValue);

  final String storageValue;

  static const String legacyManagedStorageValue = 'agent';

  String label(AppLocalizations l10n) {
    return switch (this) {
      CronScriptType.command => l10n.cronScriptTypeCommand,
      CronScriptType.script => l10n.cronScriptTypeScript,
      CronScriptType.managed => l10n.cronScriptTypeManaged,
    };
  }

  static CronScriptType? fromStorage(String? value) {
    if (value == legacyManagedStorageValue) return CronScriptType.managed;
    return enumByStorageValue(values, value, (type) => type.storageValue);
  }
}

/// 定时任务运行状态。
enum CronJobStatus {
  running('running'),
  paused('paused'),
  failed('failed'),
  error('error'),
  idle('idle');

  const CronJobStatus(this.storageValue);

  final String storageValue;

  String label(AppLocalizations l10n) {
    return switch (this) {
      CronJobStatus.running => l10n.cronJobStatusRunning,
      CronJobStatus.paused => l10n.cronJobStatusPaused,
      CronJobStatus.failed => l10n.cronJobStatusFailed,
      CronJobStatus.error => l10n.cronJobStatusError,
      CronJobStatus.idle => l10n.cronJobStatusIdle,
    };
  }

  static CronJobStatus fromStorage(String? value) {
    return enumByStorageValueOr(
      values,
      value,
      (status) => status.storageValue,
      fallback: CronJobStatus.idle,
    );
  }
}

/// 定时任务通知类型。
enum CronNotifyType {
  none('none'),
  log('log'),
  system('system'),
  appNotification('app_notification');

  const CronNotifyType(this.storageValue);

  final String storageValue;

  String label(AppLocalizations l10n) {
    return switch (this) {
      CronNotifyType.none => l10n.cronNotifyTypeNone,
      CronNotifyType.log => l10n.cronNotifyTypeLog,
      CronNotifyType.system => l10n.cronNotifyTypeSystem,
      CronNotifyType.appNotification => l10n.cronNotifyTypeAppNotification,
    };
  }

  static CronNotifyType fromStorage(String? value) {
    return enumByStorageValueOr(
      values,
      value,
      (type) => type.storageValue,
      fallback: CronNotifyType.log,
    );
  }
}

/// 定时任务通知级别。
enum CronNotifySeverity {
  info('info'),
  success('success'),
  warning('warning'),
  error('error'),
  critical('critical');

  const CronNotifySeverity(this.storageValue);

  final String storageValue;

  String label(AppLocalizations l10n) {
    return switch (this) {
      CronNotifySeverity.info => l10n.cronNotifySeverityInfo,
      CronNotifySeverity.success => l10n.cronNotifySeveritySuccess,
      CronNotifySeverity.warning => l10n.cronNotifySeverityWarning,
      CronNotifySeverity.error => l10n.cronNotifySeverityError,
      CronNotifySeverity.critical => l10n.cronNotifySeverityCritical,
    };
  }

  static CronNotifySeverity fromStorage(
    String? value, {
    CronNotifySeverity fallback = CronNotifySeverity.info,
  }) {
    return enumByStorageValueOr(
      values,
      value,
      (severity) => severity.storageValue,
      fallback: fallback,
    );
  }
}

/// 单个定时任务配置。
class CronEntry {
  const CronEntry({
    required this.id,
    required this.name,
    this.description = '',
    this.scriptType = CronScriptType.command,
    this.scriptPath,
    this.scriptContent,
    this.cronExpression = '* * * * *',
    this.retryCount = kCronDefaultRetryCount,
    this.timeoutSeconds = kCronDefaultTimeoutSeconds,
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
    this.maxRetryDelaySeconds = kCronDefaultRetryDelaySeconds,
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
      retryCount: _cronRetryCountRange.fromValue(json['retry_count']),
      timeoutSeconds: _cronTimeoutSecondsRange.fromValue(
        json['timeout_seconds'],
      ),
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
      maxRetryDelaySeconds: _cronRetryDelaySecondsRange.fromValue(
        json['max_retry_delay_seconds'],
      ),
      lastRunAt: dateTimeFromValue(json['last_run_at']),
      nextRunAt: dateTimeFromValue(json['next_run_at']),
      lastExitCode: optionalIntFromValue(json['last_exit_code']),
      consecutiveFailures: _cronNonNegativeCounter(
        json['consecutive_failures'],
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

/// 单次定时任务执行记录。
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
      elapsedMs: _cronNonNegativeCounter(json['elapsed_ms']),
      retryAttempt: _cronNonNegativeCounter(json['retry_attempt']),
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

  /// 取值：success、failed、timed_out、running、killed。
  final String status;
  final int? exitCode;
  final String stdout;
  final String stderr;
  final String? errorMessage;
  final int elapsedMs;
  final int retryAttempt;
  final String? runAsUser;
  final String? workingDirectory;

  /// 任务配置的脚本环境变量覆盖项。
  final Map<String, String> environment;

  /// 执行时采集的应用与主机上下文。
  final Map<String, String> appContext;

  /// 执行时采集的进程环境快照。
  final Map<String, String> environmentSnapshot;

  final int? pid;

  /// 取值：scheduled、manual。
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

int _cronNonNegativeCounter(Object? value) {
  return nonNegativeIntFromValue(value, fallback: 0);
}
