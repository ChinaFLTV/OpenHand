import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../shared/util/input_value_parsing.dart';

enum AiExposureServiceLifecycle { stopped, starting, running, stopping, error }

enum AiExposureSource {
  manual('manual'),
  github('github'),
  githubArtifact('github_artifact'),
  gitee('gitee'),
  gitcode('gitcode'),
  fofa('fofa'),
  shodan('shodan'),
  nodeseek('nodeseek'),
  linuxDo('linux_do'),
  v2ex('v2ex');

  const AiExposureSource(this.id);
  final String id;

  static AiExposureSource fromId(Object? value) =>
      enumByStorageValueOr(values, value, (item) => item.id, fallback: manual);
}

enum AiExposureScanMode {
  incremental('incremental'),
  full('full');

  const AiExposureScanMode(this.id);
  final String id;

  static AiExposureScanMode fromId(Object? value) => enumByStorageValueOr(
    values,
    value,
    (item) => item.id,
    fallback: incremental,
  );
}

enum AiExposureValidationMode {
  passive('passive'),
  authorizedActive('authorized_active');

  const AiExposureValidationMode(this.id);
  final String id;

  static AiExposureValidationMode fromId(Object? value) =>
      tryFromId(value) ?? passive;

  static AiExposureValidationMode? tryFromId(Object? value) =>
      enumByStorageValue(values, value, (item) => item.id);
}

enum AiExposureForumFetchMode {
  jinaFallback('jina_fallback'),
  playwright('playwright'),
  cdp('cdp');

  const AiExposureForumFetchMode(this.id);
  final String id;

  static AiExposureForumFetchMode fromId(Object? value) =>
      tryFromId(value) ?? jinaFallback;

  static AiExposureForumFetchMode? tryFromId(Object? value) =>
      enumByStorageValue(values, value, (item) => item.id);
}

const int kAiExposureMaxToolProfiles = 32;

enum AiExposureTool {
  github('github'),
  gitee('gitee'),
  gitcode('gitcode'),
  fofa('fofa'),
  shodan('shodan'),
  jina('jina');

  const AiExposureTool(this.id);
  final String id;

  static AiExposureTool fromId(Object? value) =>
      enumByStorageValueOr(values, value, (item) => item.id, fallback: github);
}

enum AiExposureToolSelectionStrategy {
  roundRobin('round_robin'),
  random('random'),
  leastUsed('least_used'),
  leastBusy('least_busy'),
  highestSuccessRate('highest_success_rate');

  const AiExposureToolSelectionStrategy(this.id);
  final String id;

  static AiExposureToolSelectionStrategy fromId(Object? value) =>
      enumByStorageValueOr(
        values,
        value,
        (item) => item.id,
        fallback: roundRobin,
      );
}

class AiExposureToolProfile {
  const AiExposureToolProfile({
    required this.id,
    required this.name,
    required this.enabled,
    required this.values,
  });

  factory AiExposureToolProfile.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final rawValues = json['values'];
    return AiExposureToolProfile(
      id: _stringValue(json['id']),
      name: _stringValue(json['name'], fallback: '配置'),
      enabled: _boolValue(json['enabled'], fallback: true),
      values: rawValues is Map
          ? <String, String>{
              for (final entry in rawValues.entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            }
          : const <String, String>{},
    );
  }

  final String id;
  final String name;
  final bool enabled;
  final Map<String, String> values;

  AiExposureToolProfile copyWith({
    String? id,
    String? name,
    bool? enabled,
    Map<String, String>? values,
  }) => AiExposureToolProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    values: values ?? this.values,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.trim(),
    'name': name.trim(),
    'enabled': enabled,
    'values': <String, String>{
      for (final entry in values.entries)
        if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
          entry.key.trim(): entry.value.trim(),
    },
  };
}

class AiExposureToolConfiguration {
  const AiExposureToolConfiguration({
    required this.tool,
    required this.enabled,
    required this.strategy,
    required this.profiles,
  });

  factory AiExposureToolConfiguration.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    return AiExposureToolConfiguration(
      tool: AiExposureTool.fromId(json['tool']),
      enabled: _boolValue(json['enabled'], fallback: true),
      strategy: AiExposureToolSelectionStrategy.fromId(json['strategy']),
      profiles: _objectList(json['profiles'])
          .map(AiExposureToolProfile.fromJson)
          .where((profile) => profile.id.trim().isNotEmpty)
          .take(kAiExposureMaxToolProfiles)
          .toList(growable: false),
    );
  }

  final AiExposureTool tool;
  final bool enabled;
  final AiExposureToolSelectionStrategy strategy;
  final List<AiExposureToolProfile> profiles;

  AiExposureToolConfiguration copyWith({
    bool? enabled,
    AiExposureToolSelectionStrategy? strategy,
    List<AiExposureToolProfile>? profiles,
  }) => AiExposureToolConfiguration(
    tool: tool,
    enabled: enabled ?? this.enabled,
    strategy: strategy ?? this.strategy,
    profiles: profiles ?? this.profiles,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'tool': tool.id,
    'enabled': enabled,
    'strategy': strategy.id,
    'profiles': profiles
        .take(kAiExposureMaxToolProfiles)
        .map((profile) => profile.toJson())
        .toList(growable: false),
  };
}

class AiExposureToolSettings {
  const AiExposureToolSettings({required this.tools});

  factory AiExposureToolSettings.defaults() => AiExposureToolSettings(
    tools: <AiExposureToolConfiguration>[
      for (final tool in AiExposureTool.values)
        AiExposureToolConfiguration(
          tool: tool,
          enabled: true,
          strategy: AiExposureToolSelectionStrategy.roundRobin,
          profiles: tool == AiExposureTool.jina
              ? const <AiExposureToolProfile>[
                  AiExposureToolProfile(
                    id: 'jina-default',
                    name: '默认配置',
                    enabled: true,
                    values: <String, String>{},
                  ),
                ]
              : const <AiExposureToolProfile>[],
        ),
    ],
  );

  factory AiExposureToolSettings.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final decoded = _objectList(
      json['tools'],
    ).map(AiExposureToolConfiguration.fromJson).toList(growable: false);
    return AiExposureToolSettings(tools: decoded).normalized();
  }

  factory AiExposureToolSettings.fromLegacy(Map<String, String> credentials) {
    final profiles = <AiExposureTool, List<AiExposureToolProfile>>{};
    void addProfiles(AiExposureTool tool, List<Map<String, String>> values) {
      if (values.isEmpty) return;
      profiles[tool] = <AiExposureToolProfile>[
        for (var index = 0; index < values.length; index++)
          AiExposureToolProfile(
            id: 'legacy-${tool.id}-${index + 1}',
            name: '配置 ${index + 1}',
            enabled: true,
            values: values[index],
          ),
      ];
    }

    addProfiles(
      AiExposureTool.github,
      _legacyToolValues(credentials['githubToken'], 'token'),
    );
    addProfiles(
      AiExposureTool.gitee,
      _legacyToolValues(credentials['giteeToken'], 'token'),
    );
    addProfiles(
      AiExposureTool.gitcode,
      _legacyToolValues(credentials['gitcodeToken'], 'token'),
    );
    final fofaEmail = credentials['fofaEmail']?.trim() ?? '';
    final fofaProfiles = _legacyToolValues(credentials['fofaKey'], 'key')
        .map((values) => <String, String>{'email': fofaEmail, ...values})
        .toList(growable: true);
    if (fofaProfiles.isEmpty && fofaEmail.isNotEmpty) {
      fofaProfiles.add(<String, String>{'email': fofaEmail});
    }
    addProfiles(AiExposureTool.fofa, fofaProfiles);
    addProfiles(
      AiExposureTool.shodan,
      _legacyToolValues(credentials['shodanKey'], 'key'),
    );
    return AiExposureToolSettings(
      tools: <AiExposureToolConfiguration>[
        for (final tool in AiExposureTool.values)
          AiExposureToolConfiguration(
            tool: tool,
            enabled: true,
            strategy: AiExposureToolSelectionStrategy.roundRobin,
            profiles:
                profiles[tool] ??
                (tool == AiExposureTool.jina
                    ? const <AiExposureToolProfile>[
                        AiExposureToolProfile(
                          id: 'jina-default',
                          name: '默认配置',
                          enabled: true,
                          values: <String, String>{},
                        ),
                      ]
                    : const <AiExposureToolProfile>[]),
          ),
      ],
    );
  }

  final List<AiExposureToolConfiguration> tools;

  AiExposureToolConfiguration configuration(AiExposureTool tool) =>
      tools.firstWhere(
        (configuration) => configuration.tool == tool,
        orElse: () => AiExposureToolSettings.defaults().tools.firstWhere(
          (configuration) => configuration.tool == tool,
        ),
      );

  AiExposureToolSettings replace(AiExposureToolConfiguration configuration) =>
      AiExposureToolSettings(
        tools: <AiExposureToolConfiguration>[
          for (final tool in AiExposureTool.values)
            tool == configuration.tool
                ? configuration
                : this.configuration(tool),
        ],
      );

  AiExposureToolSettings normalized() {
    final byTool = <AiExposureTool, AiExposureToolConfiguration>{};
    for (final configuration in tools) {
      byTool.putIfAbsent(configuration.tool, () => configuration);
    }
    final defaults = AiExposureToolSettings.defaults();
    return AiExposureToolSettings(
      tools: <AiExposureToolConfiguration>[
        for (final tool in AiExposureTool.values)
          byTool[tool] ?? defaults.configuration(tool),
      ],
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'tools': normalized().tools
        .map((configuration) => configuration.toJson())
        .toList(growable: false),
  };
}

List<Map<String, String>> _legacyToolValues(String? raw, String key) {
  final values = raw
      ?.split(RegExp(r'[,\s]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .take(kAiExposureMaxToolProfiles)
      .toList(growable: false);
  return <Map<String, String>>[
    for (final value in values ?? const <String>[])
      <String, String>{key: value},
  ];
}

enum AiExposureResultCategory {
  valid('valid'),
  suspicious('suspicious'),
  highValue('high_value'),
  honeypot('honeypot');

  const AiExposureResultCategory(this.id);

  /// 与扫描引擎对齐的线路取值。导出与回读共用，避免 `.name`（highValue）与
  /// 引擎线路值（high_value）漂移导致回读降级。
  final String id;

  static AiExposureResultCategory fromId(Object? value) => enumByStorageValueOr(
    values,
    value,
    (item) => item.id,
    fallback: suspicious,
  );
}

const Set<String> _kAiExposureTerminalStages = <String>{
  'completed',
  'failed',
  'cancelled',
};
const int _kAiExposureMaxTelemetryDurationMs = 600000;
const int _kAiExposureMaxEpochMs = 8640000000000000;
const int _kAiExposureMinHttpStatus = 100;
const int _kAiExposureMaxHttpStatus = 599;

bool isAiExposureTerminalStage(String stage) =>
    _kAiExposureTerminalStages.contains(stage);

enum AiExposureContentEncoding {
  base64('base64'),
  base64Url('base64_url'),
  url('url'),
  hex('hex');

  const AiExposureContentEncoding(this.id);
  final String id;

  static AiExposureContentEncoding? tryFromId(Object? value) =>
      enumByStorageValue(values, value, (item) => item.id);
}

enum AiExposureProxyStrategy {
  fixed('fixed'),
  roundRobin('round_robin'),
  random('random'),
  stickyHost('sticky_host');

  const AiExposureProxyStrategy(this.id);
  final String id;

  static AiExposureProxyStrategy fromId(Object? value) => enumByStorageValueOr(
    values,
    value,
    (item) => item.id,
    fallback: roundRobin,
  );
}

/// 代理底层请求时使用的路由来源。
enum AiExposureProxyMode {
  pool('pool'),
  system('system');

  const AiExposureProxyMode(this.id);
  final String id;

  static AiExposureProxyMode fromId(Object? value) =>
      enumByStorageValueOr(values, value, (item) => item.id, fallback: pool);
}

enum AiExposureProxyRoute { pool, system, direct }

class AiExposureHealth {
  const AiExposureHealth({
    required this.version,
    required this.databasePath,
    required this.uptimeSeconds,
  });

  factory AiExposureHealth.fromJson(Map<String, Object?> json) =>
      AiExposureHealth(
        version: _stringValue(json['version']),
        databasePath: _stringValue(json['databasePath']),
        uptimeSeconds: _nonNegativeInt(json['uptimeSeconds']),
      );

  final String version;
  final String databasePath;
  final int uptimeSeconds;
}

class AiExposureProgress {
  const AiExposureProgress({
    required this.jobId,
    required this.stage,
    required this.discovered,
    required this.candidates,
    required this.valid,
    required this.highValue,
    required this.processed,
    required this.total,
    required this.message,
    required this.updatedAt,
    this.updatedAtReported = true,
    this.failureStage,
    this.stageTimings = const <AiExposureStageTiming>[],
  });

  factory AiExposureProgress.fromJson(Map<String, Object?> json) {
    final updatedAt = _optionalDateTime(json['updatedAt']);
    return AiExposureProgress(
      jobId: _stringValue(json['jobId']),
      stage: _stringValue(json['stage'], fallback: 'queued'),
      discovered: _nonNegativeInt(json['discovered']),
      candidates: _nonNegativeInt(json['candidates']),
      valid: _nonNegativeInt(json['valid']),
      highValue: _nonNegativeInt(json['highValue']),
      processed: _nonNegativeInt(json['processed']),
      total: _nonNegativeInt(json['total']),
      message: _stringValue(json['message']),
      updatedAt: updatedAt ?? DateTime.now(),
      updatedAtReported: updatedAt != null,
      failureStage: _optionalString(json['failureStage']),
      stageTimings: _objectList(
        json['stageTimings'],
      ).map(AiExposureStageTiming.fromJson).toList(growable: false),
    );
  }

  final String jobId;
  final String stage;
  final int discovered;
  final int candidates;
  final int valid;
  final int highValue;
  final int processed;
  final int total;
  final String message;
  final DateTime updatedAt;
  final bool updatedAtReported;
  final String? failureStage;
  final List<AiExposureStageTiming> stageTimings;

  DateTime? get reportedUpdatedAt => updatedAtReported ? updatedAt : null;
  double get fraction => total <= 0 ? 0 : (processed / total).clamp(0, 1);
  double? get displayFraction => isRunning && total <= 0
      ? null
      : stage == 'completed'
      ? 1
      : fraction;
  bool get isRunning => !isAiExposureTerminalStage(stage);
}

class AiExposureStageTiming {
  const AiExposureStageTiming({
    required this.stage,
    this.startedAt,
    this.finishedAt,
    this.durationMs,
    this.inputCount,
    this.outputCount,
    this.message,
  });

  factory AiExposureStageTiming.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    return AiExposureStageTiming(
      stage: _stringValue(json['stage']),
      startedAt: _optionalDateTime(json['startedAt']),
      finishedAt: _optionalDateTime(json['finishedAt']),
      durationMs: _optionalNonNegativeInt(json['durationMs']),
      inputCount: _optionalNonNegativeInt(json['inputCount']),
      outputCount: _optionalNonNegativeInt(json['outputCount']),
      message: _optionalString(json['message']),
    );
  }

  final String stage;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? durationMs;
  final int? inputCount;
  final int? outputCount;
  final String? message;
}

class AiExposureQuota {
  const AiExposureQuota({
    required this.source,
    required this.configured,
    required this.available,
    required this.message,
    this.remaining,
    this.limit,
    this.resetsAt,
    this.checkedAt,
    this.latencyMs,
    this.httpStatus,
    this.errorCode,
    this.lastSuccessAt,
    this.lastFailureAt,
  });

  factory AiExposureQuota.fromJson(Map<String, Object?> json) =>
      AiExposureQuota(
        source: AiExposureSource.fromId(_optionalString(json['source'])),
        configured: _boolValue(json['configured']),
        available: _boolValue(json['available']),
        remaining: _optionalNonNegativeInt(json['remaining']),
        limit: _optionalNonNegativeInt(json['limit']),
        resetsAt: _optionalDateTime(json['resetsAt']),
        message: _stringValue(json['message']),
        checkedAt: _optionalDateTime(json['checkedAt']),
        latencyMs: _optionalNonNegativeInt(
          json['latencyMs'],
          max: _kAiExposureMaxTelemetryDurationMs,
        ),
        httpStatus: _optionalHttpStatus(json['httpStatus']),
        errorCode: _optionalString(json['errorCode']),
        lastSuccessAt: _optionalDateTime(json['lastSuccessAt']),
        lastFailureAt: _optionalDateTime(json['lastFailureAt']),
      );

  final AiExposureSource source;
  final bool configured;
  final bool available;
  final int? remaining;
  final int? limit;
  final DateTime? resetsAt;
  final String message;
  final DateTime? checkedAt;
  final int? latencyMs;
  final int? httpStatus;
  final String? errorCode;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
}

class AiExposureScanRule {
  const AiExposureScanRule({
    required this.id,
    required this.vendor,
    required this.protocol,
    required this.enabled,
    required this.credentialPatterns,
    required this.contextTerms,
    this.contentEncodings = const <AiExposureContentEncoding>[],
    required this.modelPaths,
    required this.balancePaths,
    this.version,
    this.contentHash,
    this.createdAt,
    this.updatedAt,
    this.snapshotId,
    this.changeSource,
  });

  factory AiExposureScanRule.fromJson(Map<String, Object?> json) =>
      AiExposureScanRule(
        id: _stringValue(json['id']),
        vendor: _stringValue(json['vendor']),
        protocol: _stringValue(json['protocol']),
        enabled: _boolValue(json['enabled'], fallback: true),
        credentialPatterns: _stringList(json['credentialPatterns']),
        contextTerms: _stringList(json['contextTerms']),
        contentEncodings: _stringList(json['contentEncodings'])
            .map(AiExposureContentEncoding.tryFromId)
            .whereType<AiExposureContentEncoding>()
            .toList(growable: false),
        modelPaths: _stringList(json['modelPaths']),
        balancePaths: _stringList(json['balancePaths']),
        version: _optionalString(json['version']),
        contentHash: _optionalString(json['contentHash']),
        createdAt: _optionalDateTime(json['createdAt']),
        updatedAt: _optionalDateTime(json['updatedAt']),
        snapshotId: _optionalString(json['snapshotId']),
        changeSource: _optionalString(json['changeSource']),
      );

  final String id;
  final String vendor;
  final String protocol;
  final bool enabled;
  final List<String> credentialPatterns;
  final List<String> contextTerms;
  final List<AiExposureContentEncoding> contentEncodings;
  final List<String> modelPaths;
  final List<String> balancePaths;
  final String? version;
  final String? contentHash;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? snapshotId;
  final String? changeSource;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'vendor': vendor,
    'protocol': protocol,
    'enabled': enabled,
    'credentialPatterns': credentialPatterns,
    'contextTerms': contextTerms,
    'contentEncodings': contentEncodings
        .map((encoding) => encoding.id)
        .toList(growable: false),
    'modelPaths': modelPaths,
    'balancePaths': balancePaths,
    if (version != null) 'version': version,
    if (contentHash != null) 'contentHash': contentHash,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    if (snapshotId != null) 'snapshotId': snapshotId,
    if (changeSource != null) 'changeSource': changeSource,
  };

  AiExposureScanRule copyWith({
    bool? enabled,
    List<String>? credentialPatterns,
    List<String>? contextTerms,
    List<AiExposureContentEncoding>? contentEncodings,
    List<String>? modelPaths,
    List<String>? balancePaths,
  }) => AiExposureScanRule(
    id: id,
    vendor: vendor,
    protocol: protocol,
    enabled: enabled ?? this.enabled,
    credentialPatterns: credentialPatterns ?? this.credentialPatterns,
    contextTerms: contextTerms ?? this.contextTerms,
    contentEncodings: contentEncodings ?? this.contentEncodings,
    modelPaths: modelPaths ?? this.modelPaths,
    balancePaths: balancePaths ?? this.balancePaths,
    version: version,
    contentHash: contentHash,
    createdAt: createdAt,
    updatedAt: updatedAt,
    snapshotId: snapshotId,
    changeSource: changeSource,
  );
}

const int kAiExposureProxyLatencySampleLimit = 24;
const int kAiExposureProxyRequestSampleLimit = 24;
const int kAiExposureProxyRuntimeRequestSampleLimit = 512;
const int kAiExposureMaxProxyEndpoints = 10000;
const int kAiExposureMaxProxyRotationEvery = 10000;
const int kAiExposureMaxProxyInspectionIntervalMinutes = 24 * 60;
const int kAiExposureMaxProxyInspectionConcurrency = 32;
const int kAiExposureMaxScanConcurrency = 128;

/// 代理请求明细的持久化上限，避免长期运行导致数据库无限增长。
const int kAiExposureProxyRequestHistoryLimit = 50000;
const int kAiExposureProxyRequestHistoryPageMax = 200;

enum AiExposureProxyProbeFailure {
  gateway('gateway'),
  authentication('authentication'),
  access('access'),
  forwarding('forwarding'),
  protocol('protocol'),
  timeout('timeout');

  const AiExposureProxyProbeFailure(this.id);

  final String id;

  static AiExposureProxyProbeFailure? tryFromId(Object? value) =>
      enumByStorageValue(values, value, (item) => item.id);
}

class AiExposureProxyProbeStepResult {
  const AiExposureProxyProbeStepResult({
    required this.step,
    required this.succeeded,
    this.startedAt,
    this.finishedAt,
    this.durationMs,
    this.message,
  });

  factory AiExposureProxyProbeStepResult.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    return AiExposureProxyProbeStepResult(
      step: _stringValue(json['step']),
      succeeded: _boolValue(json['succeeded']),
      startedAt: _optionalDateTime(json['startedAt']),
      finishedAt: _optionalDateTime(json['finishedAt']),
      durationMs: _optionalNonNegativeInt(
        json['durationMs'],
        max: _kAiExposureMaxTelemetryDurationMs,
      ),
      message: _optionalString(json['message']),
    );
  }

  final String step;
  final bool succeeded;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? durationMs;
  final String? message;

  Map<String, Object?> toJson() => <String, Object?>{
    'step': step,
    'succeeded': succeeded,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
    if (durationMs != null) 'durationMs': durationMs,
    if (message != null) 'message': message,
  };
}

class AiExposureProxyProbeSample {
  const AiExposureProxyProbeSample({
    required this.checkedAt,
    this.checkedAtReported = true,
    this.latencyMs,
    this.statusCode,
    this.gatewayReachable = false,
    this.failure,
    this.error,
    this.id,
    this.inspectionRunId,
    this.scheduledAt,
    this.startedAt,
    this.finishedAt,
    this.stepResults = const <AiExposureProxyProbeStepResult>[],
  });

  factory AiExposureProxyProbeSample.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final latencyMs = _optionalNonNegativeInt(
      json['latencyMs'],
      max: _kAiExposureMaxTelemetryDurationMs,
    );
    final statusCode = _optionalHttpStatus(json['statusCode']);
    final checkedAt = _optionalDateTime(json['checkedAt']);
    return AiExposureProxyProbeSample(
      checkedAt: checkedAt ?? DateTime.now(),
      checkedAtReported: checkedAt != null,
      latencyMs: latencyMs,
      statusCode: statusCode,
      gatewayReachable:
          _optionalBool(json['gatewayReachable']) ??
          latencyMs != null || statusCode != null,
      failure: AiExposureProxyProbeFailure.tryFromId(
        _optionalString(json['failure']),
      ),
      error: _optionalString(json['error']),
      id: _optionalString(json['id']),
      inspectionRunId: _optionalString(json['inspectionRunId']),
      scheduledAt: _optionalDateTime(json['scheduledAt']),
      startedAt: _optionalDateTime(json['startedAt']),
      finishedAt: _optionalDateTime(json['finishedAt']),
      stepResults: _objectList(
        json['stepResults'],
      ).map(AiExposureProxyProbeStepResult.fromJson).toList(growable: false),
    );
  }

  final DateTime checkedAt;
  final bool checkedAtReported;
  final int? latencyMs;
  final int? statusCode;
  final bool gatewayReachable;
  final AiExposureProxyProbeFailure? failure;
  final String? error;
  final String? id;
  final String? inspectionRunId;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<AiExposureProxyProbeStepResult> stepResults;

  bool get reachable => latencyMs != null && error == null;

  Map<String, Object?> toJson() => <String, Object?>{
    if (checkedAtReported) 'checkedAt': checkedAt.toIso8601String(),
    if (latencyMs != null) 'latencyMs': latencyMs,
    if (statusCode != null) 'statusCode': statusCode,
    if (gatewayReachable) 'gatewayReachable': true,
    if (failure != null) 'failure': failure!.id,
    if (error?.isNotEmpty == true) 'error': error,
    if (id != null) 'id': id,
    if (inspectionRunId != null) 'inspectionRunId': inspectionRunId,
    if (scheduledAt != null) 'scheduledAt': scheduledAt!.toIso8601String(),
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
    if (stepResults.isNotEmpty)
      'stepResults': stepResults.map((step) => step.toJson()).toList(),
  };
}

class AiExposureProxyRequestSample {
  const AiExposureProxyRequestSample({
    required this.at,
    this.atReported = true,
    required this.result,
    required this.responseTimeMs,
    this.statusCode,
    this.id,
    this.endpointId,
    this.clientIp,
    this.clientPort,
    this.remoteIp,
    this.targetHost,
    this.method,
    this.timeoutMs,
    this.errorType,
    this.errorMessage,
    this.routeMode,
    this.selectionReason,
    this.context,
  });

  factory AiExposureProxyRequestSample.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final milliseconds = _nonNegativeInt(
      json['atMs'],
      max: _kAiExposureMaxEpochMs,
    );
    final rawResult = _optionalString(json['result']);
    final result =
        const <String>{'success', 'failure', 'timeout'}.contains(rawResult)
        ? rawResult!
        : 'failure';
    final statusCode = _optionalHttpStatus(json['statusCode']);
    final atReported = milliseconds > 0;
    return AiExposureProxyRequestSample(
      at: atReported
          ? DateTime.fromMillisecondsSinceEpoch(milliseconds)
          : DateTime.now(),
      atReported: atReported,
      result: result,
      responseTimeMs: _nonNegativeInt(
        json['responseTimeMs'],
        max: _kAiExposureMaxTelemetryDurationMs,
      ),
      statusCode: statusCode,
      id: _optionalString(json['id']),
      endpointId: _optionalString(json['endpointId']),
      clientIp: _optionalString(json['clientIp']),
      clientPort: _optionalString(json['clientPort']),
      remoteIp: _optionalString(json['remoteIp']),
      targetHost: _optionalString(json['targetHost']),
      method: _optionalString(json['method']),
      timeoutMs: _optionalNonNegativeInt(
        json['timeoutMs'],
        max: _kAiExposureMaxTelemetryDurationMs,
      ),
      errorType: _optionalString(json['errorType']),
      errorMessage: _optionalString(json['errorMessage']),
      routeMode: _optionalString(json['routeMode']),
      selectionReason: _optionalString(json['selectionReason']),
      context: _optionalString(json['context']),
    );
  }

  final DateTime at;
  final bool atReported;
  final String result;
  final int responseTimeMs;
  final int? statusCode;
  final String? id;
  final String? endpointId;
  final String? clientIp;
  final String? clientPort;
  final String? remoteIp;
  final String? targetHost;
  final String? method;
  final int? timeoutMs;
  final String? errorType;
  final String? errorMessage;
  final String? routeMode;
  final String? selectionReason;
  final String? context;

  bool get succeeded => result == 'success';
  bool get timedOut => result == 'timeout';

  Map<String, Object?> toJson() => <String, Object?>{
    if (atReported) 'atMs': at.millisecondsSinceEpoch,
    'result': result,
    'responseTimeMs': responseTimeMs,
    if (statusCode != null) 'statusCode': statusCode,
    if (id != null) 'id': id,
    if (endpointId != null) 'endpointId': endpointId,
    if (clientIp != null) 'clientIp': clientIp,
    if (clientPort != null) 'clientPort': clientPort,
    if (remoteIp != null) 'remoteIp': remoteIp,
    if (targetHost != null) 'targetHost': targetHost,
    if (method != null) 'method': method,
    if (timeoutMs != null) 'timeoutMs': timeoutMs,
    if (errorType != null) 'errorType': errorType,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (routeMode != null) 'routeMode': routeMode,
    if (selectionReason != null) 'selectionReason': selectionReason,
    if (context != null) 'context': context,
  };
}

/// 代理请求明细记录。请求样本与节点地址分开存储，节点被移除后仍可追溯历史。
class AiExposureProxyRequestRecord {
  const AiExposureProxyRequestRecord({
    required this.endpointUrl,
    required this.sample,
  });

  final String endpointUrl;
  final AiExposureProxyRequestSample sample;

  String get recordId {
    final id = sample.id?.trim();
    if (id != null && id.isNotEmpty) return id;
    return '${endpointUrl}_${sample.at.millisecondsSinceEpoch}_'
        '${sample.result}_${sample.responseTimeMs}_${sample.targetHost ?? ''}';
  }

  String get clientIp => sample.clientIp?.trim().isNotEmpty == true
      ? sample.clientIp!.trim()
      : '--';

  String get clientEndpoint =>
      aiExposureProxyClientEndpoint(sample.clientIp, sample.clientPort);

  String get proxyNode {
    final value = endpointUrl.trim();
    if (value.isEmpty) return '--';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.userInfo.isEmpty) return value;
    final username = uri.userInfo.split(':').first;
    return uri.replace(userInfo: '$username:******').toString();
  }

  String get remoteIp {
    final remoteIp = sample.remoteIp?.trim();
    if (remoteIp?.isNotEmpty == true) return remoteIp!;
    final targetHost = sample.targetHost?.trim();
    return targetHost?.isNotEmpty == true ? targetHost! : '--';
  }

  String get note {
    final message = sample.errorMessage?.trim();
    if (message?.isNotEmpty == true) return message!;
    final context = sample.context?.trim();
    return context?.isNotEmpty == true ? context! : '--';
  }
}

String aiExposureProxyClientEndpoint(String? ipValue, String? portValue) {
  final ip = ipValue?.trim() ?? '';
  if (ip.isEmpty) return '--';
  final port = portValue?.trim() ?? '';
  final host = ip.contains(':') && !ip.startsWith('[') ? '[$ip]' : ip;
  return port.isEmpty ? host : '$host:$port';
}

class AiExposureProxyRequestTrendBucket {
  const AiExposureProxyRequestTrendBucket({
    required this.at,
    required this.total,
    required this.successes,
    required this.failures,
    required this.timeouts,
    this.totalResponseTimeMs = 0,
  });

  final DateTime at;
  final int total;
  final int successes;
  final int failures;
  final int timeouts;
  final int totalResponseTimeMs;

  int get averageResponseTimeMs =>
      total <= 0 ? 0 : (totalResponseTimeMs / total).round();
}

class AiExposureProxyUsageStatistics {
  const AiExposureProxyUsageStatistics({
    this.requests = 0,
    this.successes = 0,
    this.failures = 0,
    this.timeouts = 0,
    this.inFlight = 0,
    this.totalResponseTimeMs = 0,
    this.minResponseTimeMs = 0,
    this.maxResponseTimeMs = 0,
    this.status2xx = 0,
    this.status3xx = 0,
    this.status4xx = 0,
    this.status5xx = 0,
    this.consecutiveFailures = 0,
    this.lastUsedAt,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastError = '',
    this.recentRequests = const <AiExposureProxyRequestSample>[],
  });

  factory AiExposureProxyUsageStatistics.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final recent = _objectList(
      json['recentRequests'],
    ).map(AiExposureProxyRequestSample.fromJson).toList(growable: false);
    DateTime? timestamp(String key) {
      final value = _nonNegativeInt(json[key], max: _kAiExposureMaxEpochMs);
      return value <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(value);
    }

    return AiExposureProxyUsageStatistics(
      requests: _nonNegativeInt(json['requests']),
      successes: _nonNegativeInt(json['successes']),
      failures: _nonNegativeInt(json['failures']),
      timeouts: _nonNegativeInt(json['timeouts']),
      inFlight: _nonNegativeInt(json['inFlight']),
      totalResponseTimeMs: _nonNegativeInt(json['totalResponseTimeMs']),
      minResponseTimeMs: _nonNegativeInt(json['minResponseTimeMs']),
      maxResponseTimeMs: _nonNegativeInt(json['maxResponseTimeMs']),
      status2xx: _nonNegativeInt(json['status2xx']),
      status3xx: _nonNegativeInt(json['status3xx']),
      status4xx: _nonNegativeInt(json['status4xx']),
      status5xx: _nonNegativeInt(json['status5xx']),
      consecutiveFailures: _nonNegativeInt(json['consecutiveFailures']),
      lastUsedAt: timestamp('lastUsedAtMs'),
      lastSuccessAt: timestamp('lastSuccessAtMs'),
      lastFailureAt: timestamp('lastFailureAtMs'),
      lastError: _stringValue(json['lastError']),
      recentRequests: recent.length <= kAiExposureProxyRuntimeRequestSampleLimit
          ? recent
          : recent.sublist(
              recent.length - kAiExposureProxyRuntimeRequestSampleLimit,
            ),
    );
  }

  final int requests;
  final int successes;
  final int failures;
  final int timeouts;
  final int inFlight;
  final int totalResponseTimeMs;
  final int minResponseTimeMs;
  final int maxResponseTimeMs;
  final int status2xx;
  final int status3xx;
  final int status4xx;
  final int status5xx;
  final int consecutiveFailures;
  final DateTime? lastUsedAt;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final String lastError;
  final List<AiExposureProxyRequestSample> recentRequests;

  int get completed => successes + failures + timeouts;
  int get averageResponseTimeMs =>
      completed == 0 ? 0 : (totalResponseTimeMs / completed).round();
  double get successRate => completed == 0 ? 0 : successes / completed;

  bool hasSamePersistedState(AiExposureProxyUsageStatistics other) {
    if (requests != other.requests ||
        successes != other.successes ||
        failures != other.failures ||
        timeouts != other.timeouts ||
        totalResponseTimeMs != other.totalResponseTimeMs ||
        minResponseTimeMs != other.minResponseTimeMs ||
        maxResponseTimeMs != other.maxResponseTimeMs ||
        status2xx != other.status2xx ||
        status3xx != other.status3xx ||
        status4xx != other.status4xx ||
        status5xx != other.status5xx ||
        consecutiveFailures != other.consecutiveFailures ||
        lastUsedAt != other.lastUsedAt ||
        lastSuccessAt != other.lastSuccessAt ||
        lastFailureAt != other.lastFailureAt ||
        lastError != other.lastError ||
        recentRequests.length != other.recentRequests.length) {
      return false;
    }
    for (var index = 0; index < recentRequests.length; index++) {
      final current = recentRequests[index];
      final next = other.recentRequests[index];
      if (current.atReported != next.atReported ||
          (current.atReported && current.at != next.at) ||
          current.result != next.result ||
          current.responseTimeMs != next.responseTimeMs ||
          current.statusCode != next.statusCode ||
          current.id != next.id ||
          current.endpointId != next.endpointId ||
          current.clientIp != next.clientIp ||
          current.clientPort != next.clientPort ||
          current.remoteIp != next.remoteIp ||
          current.targetHost != next.targetHost ||
          current.method != next.method ||
          current.timeoutMs != next.timeoutMs ||
          current.errorType != next.errorType ||
          current.errorMessage != next.errorMessage ||
          current.routeMode != next.routeMode ||
          current.selectionReason != next.selectionReason ||
          current.context != next.context) {
        return false;
      }
    }
    return true;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'requests': requests,
    'successes': successes,
    'failures': failures,
    'timeouts': timeouts,
    'totalResponseTimeMs': totalResponseTimeMs,
    'minResponseTimeMs': minResponseTimeMs,
    'maxResponseTimeMs': maxResponseTimeMs,
    'status2xx': status2xx,
    'status3xx': status3xx,
    'status4xx': status4xx,
    'status5xx': status5xx,
    'consecutiveFailures': consecutiveFailures,
    'lastUsedAtMs': lastUsedAt?.millisecondsSinceEpoch ?? 0,
    'lastSuccessAtMs': lastSuccessAt?.millisecondsSinceEpoch ?? 0,
    'lastFailureAtMs': lastFailureAt?.millisecondsSinceEpoch ?? 0,
    'lastError': lastError,
    if (recentRequests.isNotEmpty)
      'recentRequests': recentRequests
          .map((item) => item.toJson())
          .toList(growable: false),
  };
}

class AiExposureProxyIdentity {
  const AiExposureProxyIdentity({
    required this.exitIp,
    required this.ipType,
    required this.networkType,
    required this.cleanliness,
    required this.continent,
    required this.country,
    required this.countryCode,
    required this.region,
    required this.city,
    required this.district,
    required this.postalCode,
    required this.timezone,
    required this.currency,
    required this.isp,
    required this.organization,
    required this.asn,
    required this.asName,
    required this.mobile,
    required this.proxy,
    required this.hosting,
    required this.latitude,
    required this.longitude,
    required this.observedAt,
    this.observedAtReported = true,
  });

  factory AiExposureProxyIdentity.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final observedAt = _optionalDateTime(json['observedAt']);
    return AiExposureProxyIdentity(
      exitIp: _stringValue(json['exitIp']),
      ipType: _stringValue(json['ipType'], fallback: '--'),
      networkType: _stringValue(json['networkType'], fallback: '--'),
      cleanliness: _stringValue(json['cleanliness'], fallback: '--'),
      continent: _stringValue(json['continent']),
      country: _stringValue(json['country']),
      countryCode: _stringValue(json['countryCode']),
      region: _stringValue(json['region']),
      city: _stringValue(json['city']),
      district: _stringValue(json['district']),
      postalCode: _stringValue(json['postalCode']),
      timezone: _stringValue(json['timezone']),
      currency: _stringValue(json['currency']),
      isp: _stringValue(json['isp']),
      organization: _stringValue(json['organization']),
      asn: _stringValue(json['asn']),
      asName: _stringValue(json['asName']),
      mobile: _boolValue(json['mobile']),
      proxy: _boolValue(json['proxy']),
      hosting: _boolValue(json['hosting']),
      latitude: _optionalFiniteDouble(json['latitude']),
      longitude: _optionalFiniteDouble(json['longitude']),
      observedAt: observedAt ?? DateTime.now(),
      observedAtReported: observedAt != null,
    );
  }

  final String exitIp;
  final String ipType;
  final String networkType;
  final String cleanliness;
  final String continent;
  final String country;
  final String countryCode;
  final String region;
  final String city;
  final String district;
  final String postalCode;
  final String timezone;
  final String currency;
  final String isp;
  final String organization;
  final String asn;
  final String asName;
  final bool mobile;
  final bool proxy;
  final bool hosting;
  final double? latitude;
  final double? longitude;
  final DateTime observedAt;
  final bool observedAtReported;

  String get location => <String>[
    country,
    region,
    city,
    district,
  ].where((item) => item.trim().isNotEmpty).join(' / ');

  Map<String, Object?> toJson() => <String, Object?>{
    'exitIp': exitIp,
    'ipType': ipType,
    'networkType': networkType,
    'cleanliness': cleanliness,
    'continent': continent,
    'country': country,
    'countryCode': countryCode,
    'region': region,
    'city': city,
    'district': district,
    'postalCode': postalCode,
    'timezone': timezone,
    'currency': currency,
    'isp': isp,
    'organization': organization,
    'asn': asn,
    'asName': asName,
    'mobile': mobile,
    'proxy': proxy,
    'hosting': hosting,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (observedAtReported) 'observedAt': observedAt.toIso8601String(),
  };
}

class AiExposureProxyEndpoint {
  const AiExposureProxyEndpoint({
    required this.url,
    this.name = '',
    this.enabled = true,
    this.samples = const <AiExposureProxyProbeSample>[],
    this.statistics = const AiExposureProxyUsageStatistics(),
    this.identity,
  });

  factory AiExposureProxyEndpoint.parse(String input) {
    final value = input.trim();
    if (value.isEmpty ||
        value.length > 2048 ||
        value.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('代理地址为空或过长。');
    }
    final compactMatch = value.contains('://')
        ? null
        : RegExp(
            r'^(\[[^\]\s]+\]|[^:\s]+):(\d+):([^:\s]+):(.*)$',
          ).firstMatch(value);
    final normalized = compactMatch == null
        ? value.contains('://')
              ? value
              : 'http://$value'
        : () {
            final port = int.tryParse(compactMatch.group(2)!);
            if (!isValidPort(port)) {
              throw const FormatException('代理端口无效。');
            }
            final username = compactMatch.group(3)!;
            final password = compactMatch.group(4)!;
            return 'http://${Uri.encodeComponent(username)}:'
                '${Uri.encodeComponent(password)}@${compactMatch.group(1)!}:$port';
          }();
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !const <String>{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('代理地址必须为 HTTP/HTTPS 的主机和端口。');
    }
    return AiExposureProxyEndpoint(
      url: uri.replace(scheme: uri.scheme.toLowerCase(), path: '').toString(),
      name: uri.host,
    );
  }

  factory AiExposureProxyEndpoint.fromJson(Object? raw) {
    if (raw is String) return AiExposureProxyEndpoint.parse(raw);
    final json = _jsonMap(raw);
    final endpoint = AiExposureProxyEndpoint.parse(_stringValue(json['url']));
    final samples = _objectList(
      json['samples'],
    ).map(AiExposureProxyProbeSample.fromJson).toList(growable: false);
    return endpoint.copyWith(
      name: json['name'] is String ? json['name'] as String : null,
      enabled: _boolValue(json['enabled'], fallback: true),
      samples: samples.length <= kAiExposureProxyLatencySampleLimit
          ? samples
          : samples.sublist(
              samples.length - kAiExposureProxyLatencySampleLimit,
            ),
      statistics: AiExposureProxyUsageStatistics.fromJson(json['statistics']),
      identity: json['identity'] == null
          ? null
          : AiExposureProxyIdentity.fromJson(json['identity']),
    );
  }

  final String url;
  final String name;
  final bool enabled;
  final List<AiExposureProxyProbeSample> samples;
  final AiExposureProxyUsageStatistics statistics;
  final AiExposureProxyIdentity? identity;

  AiExposureProxyProbeSample? get latestSample => samples.lastOrNull;

  String get maskedUrl => maskAiExposureProxyUrl(url);

  String get displayName =>
      name.trim().isEmpty ? (Uri.tryParse(url)?.host ?? '') : name.trim();

  String get runtimeId =>
      sha256.convert(utf8.encode(url)).toString().substring(0, 12);

  AiExposureProxyEndpoint copyWith({
    String? name,
    bool? enabled,
    List<AiExposureProxyProbeSample>? samples,
    AiExposureProxyUsageStatistics? statistics,
    AiExposureProxyIdentity? identity,
  }) => AiExposureProxyEndpoint(
    url: url,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    samples: List<AiExposureProxyProbeSample>.unmodifiable(
      samples ?? this.samples,
    ),
    statistics: statistics ?? this.statistics,
    identity: identity ?? this.identity,
  );

  AiExposureProxyEndpoint withSample(AiExposureProxyProbeSample sample) {
    final updated = <AiExposureProxyProbeSample>[...samples, sample];
    if (updated.length > kAiExposureProxyLatencySampleLimit) {
      updated.removeRange(
        0,
        updated.length - kAiExposureProxyLatencySampleLimit,
      );
    }
    return copyWith(samples: updated);
  }

  Map<String, Object?> toJson({
    bool includeStatistics = true,
    bool includeSamples = true,
  }) => <String, Object?>{
    'url': url,
    if (name.trim().isNotEmpty) 'name': name.trim(),
    'enabled': enabled,
    if (includeSamples && samples.isNotEmpty)
      'samples': samples
          .map((sample) => sample.toJson())
          .toList(growable: false),
    if (includeStatistics) 'statistics': statistics.toJson(),
    if (identity != null) 'identity': identity!.toJson(),
  };
}

class AiExposureProxyConfiguration {
  const AiExposureProxyConfiguration({
    required this.enabled,
    this.mode = AiExposureProxyMode.pool,
    required this.strategy,
    required this.rotationEvery,
    required this.bypassLocal,
    required this.endpoints,
    this.inspectionEnabled = false,
    this.inspectionIntervalMinutes = 30,
    this.inspectionConcurrency = 8,
  });

  factory AiExposureProxyConfiguration.defaults() =>
      const AiExposureProxyConfiguration(
        enabled: false,
        strategy: AiExposureProxyStrategy.roundRobin,
        rotationEvery: 1,
        bypassLocal: true,
        endpoints: <AiExposureProxyEndpoint>[],
      );

  factory AiExposureProxyConfiguration.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final endpoints = <AiExposureProxyEndpoint>[];
    final seen = <String>{};
    for (final value in _objectList(json['endpoints'])) {
      try {
        final endpoint = AiExposureProxyEndpoint.fromJson(value);
        if (seen.add(endpoint.url)) endpoints.add(endpoint);
      } on FormatException {
        continue;
      }
    }
    return AiExposureProxyConfiguration(
      enabled: _boolValue(json['enabled']),
      mode: AiExposureProxyMode.fromId(json['mode'] ?? json['proxyMode']),
      strategy: AiExposureProxyStrategy.fromId(
        _optionalString(json['strategy']),
      ),
      rotationEvery: _boundedInt(
        json['rotationEvery'],
        fallback: 1,
        min: 1,
        max: kAiExposureMaxProxyRotationEvery,
      ),
      bypassLocal: _boolValue(json['bypassLocal'], fallback: true),
      endpoints: List<AiExposureProxyEndpoint>.unmodifiable(endpoints),
      inspectionEnabled: _boolValue(json['inspectionEnabled']),
      inspectionIntervalMinutes: _boundedInt(
        json['inspectionIntervalMinutes'],
        fallback: 30,
        min: 1,
        max: kAiExposureMaxProxyInspectionIntervalMinutes,
      ),
      inspectionConcurrency: _boundedInt(
        json['inspectionConcurrency'],
        fallback: 8,
        min: 1,
        max: kAiExposureMaxProxyInspectionConcurrency,
      ),
    );
  }

  final bool enabled;
  final AiExposureProxyMode mode;
  final AiExposureProxyStrategy strategy;
  final int rotationEvery;
  final bool bypassLocal;
  final List<AiExposureProxyEndpoint> endpoints;
  final bool inspectionEnabled;
  final int inspectionIntervalMinutes;
  final int inspectionConcurrency;

  List<AiExposureProxyEndpoint> get activeEndpoints =>
      endpoints.where((endpoint) => endpoint.enabled).toList(growable: false);

  Map<String, Object?> toJson({
    bool includeStatistics = true,
    bool includeSamples = true,
  }) => <String, Object?>{
    'enabled': enabled,
    'mode': mode.id,
    'strategy': strategy.id,
    'rotationEvery': rotationEvery.clamp(1, kAiExposureMaxProxyRotationEvery),
    'bypassLocal': bypassLocal,
    'endpoints': endpoints
        .map(
          (endpoint) => endpoint.toJson(
            includeStatistics: includeStatistics,
            includeSamples: includeSamples,
          ),
        )
        .toList(growable: false),
    'inspectionEnabled': inspectionEnabled,
    'inspectionIntervalMinutes': inspectionIntervalMinutes.clamp(
      1,
      kAiExposureMaxProxyInspectionIntervalMinutes,
    ),
    'inspectionConcurrency': inspectionConcurrency.clamp(
      1,
      kAiExposureMaxProxyInspectionConcurrency,
    ),
  };

  Map<String, Object?> toRuntimeJson({
    Map<String, Object?> systemProxy = const <String, Object?>{},
  }) => <String, Object?>{
    'enabled': enabled,
    'mode': mode.id,
    'strategy': strategy.id,
    'rotationEvery': rotationEvery.clamp(1, kAiExposureMaxProxyRotationEvery),
    'bypassLocal': bypassLocal,
    'endpoints': activeEndpoints
        .map(
          (endpoint) => <String, Object?>{
            'url': endpoint.url,
            'statistics': endpoint.statistics.toJson(),
          },
        )
        .toList(growable: false),
    'systemProxy': systemProxy,
  };

  AiExposureProxyConfiguration copyWith({
    bool? enabled,
    AiExposureProxyMode? mode,
    AiExposureProxyStrategy? strategy,
    int? rotationEvery,
    bool? bypassLocal,
    List<AiExposureProxyEndpoint>? endpoints,
    bool? inspectionEnabled,
    int? inspectionIntervalMinutes,
    int? inspectionConcurrency,
  }) => AiExposureProxyConfiguration(
    enabled: enabled ?? this.enabled,
    mode: mode ?? this.mode,
    strategy: strategy ?? this.strategy,
    rotationEvery: rotationEvery ?? this.rotationEvery,
    bypassLocal: bypassLocal ?? this.bypassLocal,
    endpoints: List<AiExposureProxyEndpoint>.unmodifiable(
      endpoints ?? this.endpoints,
    ),
    inspectionEnabled: inspectionEnabled ?? this.inspectionEnabled,
    inspectionIntervalMinutes:
        inspectionIntervalMinutes ?? this.inspectionIntervalMinutes,
    inspectionConcurrency: inspectionConcurrency ?? this.inspectionConcurrency,
  );
}

class AiExposureProxyEndpointStatus {
  const AiExposureProxyEndpointStatus({
    required this.id,
    required this.address,
    required this.selections,
    required this.statistics,
  });

  factory AiExposureProxyEndpointStatus.fromJson(Map<String, Object?> json) =>
      AiExposureProxyEndpointStatus(
        id: _stringValue(json['id']),
        address: _stringValue(json['address']),
        selections: _nonNegativeInt(json['selections']),
        statistics: AiExposureProxyUsageStatistics.fromJson(json['statistics']),
      );

  final String id;
  final String address;
  final int selections;
  final AiExposureProxyUsageStatistics statistics;
}

class AiExposureProxyStatus {
  const AiExposureProxyStatus({
    required this.enabled,
    required this.strategy,
    required this.rotationEvery,
    required this.bypassLocal,
    required this.totalSelections,
    required this.totalSuccesses,
    required this.totalFailures,
    required this.totalTimeouts,
    required this.inFlight,
    required this.averageResponseTimeMs,
    required this.systemProxyEnabled,
    required this.endpoints,
  });

  factory AiExposureProxyStatus.fromJson(
    Map<String, Object?> json,
  ) => AiExposureProxyStatus(
    enabled: _boolValue(json['enabled']),
    strategy: AiExposureProxyStrategy.fromId(_optionalString(json['strategy'])),
    rotationEvery: _boundedInt(
      json['rotationEvery'],
      fallback: 1,
      min: 1,
      max: kAiExposureMaxProxyRotationEvery,
    ),
    bypassLocal: _boolValue(json['bypassLocal'], fallback: true),
    totalSelections: _nonNegativeInt(json['totalSelections']),
    totalSuccesses: _nonNegativeInt(json['totalSuccesses']),
    totalFailures: _nonNegativeInt(json['totalFailures']),
    totalTimeouts: _nonNegativeInt(json['totalTimeouts']),
    inFlight: _nonNegativeInt(json['inFlight']),
    averageResponseTimeMs: _nonNegativeInt(
      json['averageResponseTimeMs'],
      max: _kAiExposureMaxTelemetryDurationMs,
    ),
    systemProxyEnabled: _boolValue(json['systemProxyEnabled']),
    endpoints: _objectList(json['endpoints'])
        .map((item) => AiExposureProxyEndpointStatus.fromJson(_jsonMap(item)))
        .toList(growable: false),
  );

  final bool enabled;
  final AiExposureProxyStrategy strategy;
  final int rotationEvery;
  final bool bypassLocal;
  final int totalSelections;
  final int totalSuccesses;
  final int totalFailures;
  final int totalTimeouts;
  final int inFlight;
  final int averageResponseTimeMs;
  final bool systemProxyEnabled;
  final List<AiExposureProxyEndpointStatus> endpoints;
}

class AiExposureHistoryEntry {
  const AiExposureHistoryEntry({
    required this.id,
    required this.name,
    required this.stage,
    required this.sources,
    required this.mode,
    required this.authorizedScope,
    required this.progress,
    required this.createdAt,
    this.createdAtReported = true,
    this.finishedAt,
    this.errorMessage,
    this.startedAt,
    this.cancelledAt,
    this.cancelReason,
    this.lastCheckpointAt,
    this.failureStage,
    this.retryCount,
    this.concurrency,
    this.validationMode,
    this.forumFetchMode,
    this.gptAssisted,
    this.stageTimings = const <AiExposureStageTiming>[],
  });

  factory AiExposureHistoryEntry.fromJson(Map<String, Object?> json) {
    final createdAt = _optionalDateTime(json['createdAt']);
    return AiExposureHistoryEntry(
      id: _stringValue(json['id']),
      name: _stringValue(json['name']),
      stage: _stringValue(json['stage'], fallback: 'queued'),
      sources: _stringList(
        json['sources'],
      ).map(AiExposureSource.fromId).toList(growable: false),
      mode: AiExposureScanMode.fromId(json['mode']),
      authorizedScope: _stringList(json['authorizedScope']),
      progress: AiExposureProgress.fromJson(_jsonMap(json['progress'])),
      createdAt: createdAt ?? DateTime.now(),
      createdAtReported: createdAt != null,
      finishedAt: _optionalDateTime(json['finishedAt']),
      errorMessage: _optionalString(json['errorMessage']),
      startedAt: _optionalDateTime(json['startedAt']),
      cancelledAt: _optionalDateTime(json['cancelledAt']),
      cancelReason: _optionalString(json['cancelReason']),
      lastCheckpointAt: _optionalDateTime(json['lastCheckpointAt']),
      failureStage: _optionalString(json['failureStage']),
      retryCount: _optionalNonNegativeInt(json['retryCount']),
      concurrency: _optionalNonNegativeInt(
        json['concurrency'],
        max: kAiExposureMaxScanConcurrency,
      ),
      validationMode: AiExposureValidationMode.tryFromId(
        json['validationMode'],
      ),
      forumFetchMode: AiExposureForumFetchMode.tryFromId(
        json['forumFetchMode'],
      ),
      gptAssisted: _optionalBool(json['gptAssisted']),
      stageTimings: _objectList(
        json['stageTimings'],
      ).map(AiExposureStageTiming.fromJson).toList(growable: false),
    );
  }

  final String id;
  final String name;
  final String stage;
  final List<AiExposureSource> sources;
  final AiExposureScanMode mode;
  final List<String> authorizedScope;
  final AiExposureProgress progress;
  final DateTime createdAt;
  final bool createdAtReported;
  final DateTime? finishedAt;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final DateTime? lastCheckpointAt;
  final String? failureStage;
  final int? retryCount;
  final int? concurrency;
  final AiExposureValidationMode? validationMode;
  final AiExposureForumFetchMode? forumFetchMode;
  final bool? gptAssisted;
  final List<AiExposureStageTiming> stageTimings;

  bool get isCompleted => stage == 'completed';
  bool get isTerminal => isAiExposureTerminalStage(stage);
  bool get isResumable => !isCompleted;
  bool get isRestartable => id.isNotEmpty;
  DateTime? get reportedCreatedAt => createdAtReported ? createdAt : null;
  DateTime? get effectiveStartedAt => startedAt ?? reportedCreatedAt;
  DateTime? get effectiveFinishedAt =>
      finishedAt ??
      cancelledAt ??
      (isTerminal ? lastCheckpointAt ?? progress.reportedUpdatedAt : null);

  Duration? durationUntil(DateTime now) {
    final start = effectiveStartedAt;
    if (start == null) return null;
    final end = effectiveFinishedAt ?? now;
    return end.isBefore(start) ? null : end.difference(start);
  }
}

class AiExposureResult {
  const AiExposureResult({
    required this.id,
    required this.jobId,
    required this.source,
    required this.url,
    required this.host,
    required this.product,
    required this.category,
    required this.credentialState,
    required this.responseFingerprint,
    required this.duplicateResponseHosts,
    required this.duplicateKeyHosts,
    required this.modelCount,
    required this.evidence,
    required this.createdAt,
    this.createdAtReported = true,
    this.maskedCredential,
    this.balanceSummary,
  });

  factory AiExposureResult.fromJson(Map<String, Object?> json) {
    final createdAt = _optionalDateTime(json['createdAt']);
    return AiExposureResult(
      id: _stringValue(json['id']),
      jobId: _stringValue(json['jobId']),
      source: AiExposureSource.fromId(_optionalString(json['source'])),
      url: _stringValue(json['url']),
      host: _stringValue(json['host']),
      product: _stringValue(json['product']),
      category: AiExposureResultCategory.fromId(
        _optionalString(json['category']),
      ),
      credentialState: _stringValue(
        json['credentialState'],
        fallback: 'not_found',
      ),
      maskedCredential: _optionalString(json['maskedCredential']),
      responseFingerprint: _stringValue(json['responseFingerprint']),
      duplicateResponseHosts: _nonNegativeInt(json['duplicateResponseHosts']),
      duplicateKeyHosts: _nonNegativeInt(json['duplicateKeyHosts']),
      modelCount: _nonNegativeInt(json['modelCount']),
      balanceSummary: _optionalString(json['balanceSummary']),
      evidence: _stringList(json['evidence']),
      createdAt: createdAt ?? DateTime.now(),
      createdAtReported: createdAt != null,
    );
  }

  final String id;
  final String jobId;
  final AiExposureSource source;
  final String url;
  final String host;
  final String product;
  final AiExposureResultCategory category;
  final String credentialState;
  final String? maskedCredential;
  final String responseFingerprint;
  final int duplicateResponseHosts;
  final int duplicateKeyHosts;
  final int modelCount;
  final String? balanceSummary;
  final List<String> evidence;
  final DateTime createdAt;
  final bool createdAtReported;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'jobId': jobId,
    'source': source.id,
    'url': url,
    'host': host,
    'product': product,
    'category': category.id,
    'credentialState': credentialState,
    'maskedCredential': maskedCredential,
    'responseFingerprint': responseFingerprint,
    'duplicateResponseHosts': duplicateResponseHosts,
    'duplicateKeyHosts': duplicateKeyHosts,
    'modelCount': modelCount,
    'balanceSummary': balanceSummary,
    'evidence': evidence,
    'createdAt': createdAt.toIso8601String(),
  };
}

class AiExposureScanRequest {
  const AiExposureScanRequest({
    required this.name,
    required this.sources,
    required this.authorizationConfirmed,
    required this.vendors,
    required this.validationMode,
    required this.forumFetchMode,
    required this.concurrency,
    required this.gptAssisted,
  });

  final String name;
  final Set<AiExposureSource> sources;
  final bool authorizationConfirmed;
  final List<String> vendors;
  final AiExposureValidationMode validationMode;
  final AiExposureForumFetchMode forumFetchMode;
  final int concurrency;
  final bool gptAssisted;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'sources': sources.map((source) => source.id).toList(growable: false),
    'mode': AiExposureScanMode.full.id,
    'authorizedScope': const <String>[],
    'authorizationConfirmed': authorizationConfirmed,
    'targets': const <String>[],
    'vendors': vendors,
    'validationMode': validationMode.id,
    'forumFetchMode': forumFetchMode.id,
    'concurrency': concurrency,
    'gptAssisted': gptAssisted,
  };
}

class AiExposureLogEntry {
  const AiExposureLogEntry({
    required this.level,
    required this.message,
    required this.at,
    this.atReported = true,
    this.jobId = '',
    this.id,
    this.module,
    this.eventCode,
    this.traceId,
    this.exceptionType,
    this.stackSummary,
    this.metadata = const <String, Object?>{},
  });

  factory AiExposureLogEntry.fromJson(Map<String, Object?> json) {
    final at = _optionalDateTime(json['at']);
    return AiExposureLogEntry(
      jobId: _stringValue(json['jobId']),
      level: _stringValue(json['level'], fallback: 'info'),
      message: _stringValue(json['message']),
      at: at ?? DateTime.now(),
      atReported: at != null,
      id: _optionalString(json['id']),
      module: _optionalString(json['module']),
      eventCode: _optionalString(json['eventCode']),
      traceId: _optionalString(json['traceId']),
      exceptionType: _optionalString(json['exceptionType']),
      stackSummary: _optionalString(json['stackSummary']),
      metadata: Map<String, Object?>.unmodifiable(_jsonMap(json['metadata'])),
    );
  }

  final String jobId;
  final String level;
  final String message;
  final DateTime at;
  final bool atReported;
  final String? id;
  final String? module;
  final String? eventCode;
  final String? traceId;
  final String? exceptionType;
  final String? stackSummary;
  final Map<String, Object?> metadata;
}

class AiExposureAiExtractorStatus {
  const AiExposureAiExtractorStatus({required this.configured, this.model});

  factory AiExposureAiExtractorStatus.fromJson(Map<String, Object?> json) =>
      AiExposureAiExtractorStatus(
        configured: _boolValue(json['configured']),
        model: _optionalString(json['model']),
      );

  final bool configured;
  final String? model;
}

class AiExposureDependencyComponentStatus {
  const AiExposureDependencyComponentStatus({
    required this.configured,
    required this.connected,
    required this.message,
    this.checkedAt,
    this.latencyMs,
    this.version,
    this.endpointMasked,
    this.errorCode,
    this.telemetry = const <String, Object?>{},
  });

  factory AiExposureDependencyComponentStatus.fromJson(
    Map<String, Object?> json,
  ) => AiExposureDependencyComponentStatus(
    configured: _boolValue(json['configured']),
    connected: _boolValue(json['connected']),
    message: _stringValue(json['message']),
    checkedAt: _optionalDateTime(json['checkedAt']),
    latencyMs: _optionalNonNegativeInt(
      json['latencyMs'],
      max: _kAiExposureMaxTelemetryDurationMs,
    ),
    version: _optionalString(json['version']),
    endpointMasked: _optionalString(json['endpointMasked']),
    errorCode: _optionalString(json['errorCode']),
    telemetry: Map<String, Object?>.unmodifiable(_jsonMap(json['telemetry'])),
  );

  final bool configured;
  final bool connected;
  final String message;
  final DateTime? checkedAt;
  final int? latencyMs;
  final String? version;
  final String? endpointMasked;
  final String? errorCode;
  final Map<String, Object?> telemetry;
}

class AiExposureDependencyStatus {
  const AiExposureDependencyStatus({
    required this.postgresql,
    required this.redis,
    required this.playwright,
    required this.googleChrome,
  });

  factory AiExposureDependencyStatus.fromJson(Map<String, Object?> json) =>
      AiExposureDependencyStatus(
        postgresql: AiExposureDependencyComponentStatus.fromJson(
          _jsonMap(json['postgresql']),
        ),
        redis: AiExposureDependencyComponentStatus.fromJson(
          _jsonMap(json['redis']),
        ),
        playwright: AiExposureDependencyComponentStatus.fromJson(
          _jsonMap(json['playwright']),
        ),
        googleChrome: AiExposureDependencyComponentStatus.fromJson(
          _jsonMap(json['googleChrome']),
        ),
      );

  final AiExposureDependencyComponentStatus postgresql;
  final AiExposureDependencyComponentStatus redis;
  final AiExposureDependencyComponentStatus playwright;
  final AiExposureDependencyComponentStatus googleChrome;
}

const String kAiExposureDefaultExternalAddress = 'http://127.0.0.1:37821';

class AiExposurePreferences {
  const AiExposurePreferences({
    required this.enabledSources,
    required this.defaultConcurrency,
    required this.defaultValidationMode,
    required this.forumFetchMode,
    required this.defaultGptAssisted,
    required this.useBundledEngine,
    required this.externalAddress,
    this.postgresqlEnabled = false,
    this.redisEnabled = false,
    required this.proxyConfiguration,
  });

  factory AiExposurePreferences.defaults() => const AiExposurePreferences(
    enabledSources: <AiExposureSource>{
      AiExposureSource.manual,
      AiExposureSource.github,
    },
    defaultConcurrency: 24,
    defaultValidationMode: AiExposureValidationMode.passive,
    forumFetchMode: AiExposureForumFetchMode.jinaFallback,
    defaultGptAssisted: false,
    useBundledEngine: true,
    externalAddress: kAiExposureDefaultExternalAddress,
    proxyConfiguration: AiExposureProxyConfiguration(
      enabled: false,
      strategy: AiExposureProxyStrategy.roundRobin,
      rotationEvery: 1,
      bypassLocal: true,
      endpoints: <AiExposureProxyEndpoint>[],
    ),
  );

  factory AiExposurePreferences.fromJson(Map<String, Object?> json) {
    final sources = _stringList(
      json['enabledSources'],
    ).map(AiExposureSource.fromId).toSet();
    return AiExposurePreferences(
      enabledSources: sources.isEmpty
          ? const <AiExposureSource>{AiExposureSource.manual}
          : sources,
      defaultConcurrency: _boundedInt(
        json['defaultConcurrency'],
        fallback: 24,
        min: 1,
        max: kAiExposureMaxScanConcurrency,
      ),
      defaultValidationMode: AiExposureValidationMode.fromId(
        json['defaultValidationMode'],
      ),
      forumFetchMode: AiExposureForumFetchMode.fromId(
        _optionalString(json['forumFetchMode']),
      ),
      defaultGptAssisted: _boolValue(json['defaultGptAssisted']),
      useBundledEngine: _boolValue(json['useBundledEngine'], fallback: true),
      externalAddress:
          _optionalString(json['externalAddress']) ??
          kAiExposureDefaultExternalAddress,
      postgresqlEnabled: _boolValue(json['postgresqlEnabled']),
      redisEnabled: _boolValue(json['redisEnabled']),
      proxyConfiguration: AiExposureProxyConfiguration.fromJson(json['proxy']),
    );
  }

  final Set<AiExposureSource> enabledSources;
  final int defaultConcurrency;
  final AiExposureValidationMode defaultValidationMode;
  final AiExposureForumFetchMode forumFetchMode;
  final bool defaultGptAssisted;
  final bool useBundledEngine;
  final String externalAddress;
  final bool postgresqlEnabled;
  final bool redisEnabled;
  final AiExposureProxyConfiguration proxyConfiguration;

  Map<String, Object?> toJson({
    bool includeProxyStatistics = true,
    bool includeProxySamples = true,
  }) => <String, Object?>{
    'enabledSources': enabledSources
        .map((source) => source.id)
        .toList(growable: false),
    'defaultConcurrency': defaultConcurrency,
    'defaultValidationMode': defaultValidationMode.id,
    'forumFetchMode': forumFetchMode.id,
    'defaultGptAssisted': defaultGptAssisted,
    'useBundledEngine': useBundledEngine,
    'externalAddress': externalAddress,
    'postgresqlEnabled': postgresqlEnabled,
    'redisEnabled': redisEnabled,
    'proxy': proxyConfiguration.toJson(
      includeStatistics: includeProxyStatistics,
      includeSamples: includeProxySamples,
    ),
  };
}

Map<String, Object?> aiExposureJsonMap(Object? value) => _jsonMap(value);

/// 生成不含凭据的代理 authority；IPv6 主机自动加方括号。
String aiExposureProxyAuthority(Uri proxy) {
  final host = proxy.host.contains(':') ? '[${proxy.host}]' : proxy.host;
  return '$host:${proxy.port}';
}

/// 从 URI 的 userInfo 解析代理凭据；无分隔符时整体作为用户名、密码留空。
({String username, String password}) aiExposureProxyCredentials(
  String userInfo,
) {
  if (userInfo.isEmpty) return (username: '', password: '');
  final separator = userInfo.indexOf(':');
  if (separator < 0) {
    return (username: _decodeProxyUriComponent(userInfo), password: '');
  }
  return (
    username: _decodeProxyUriComponent(userInfo.substring(0, separator)),
    password: _decodeProxyUriComponent(userInfo.substring(separator + 1)),
  );
}

/// 对代理地址脱敏展示：保留协议、用户名、主机与端口，密码固定替换为 ******。
/// 解析失败或缺少主机时返回 [fallback]。
String maskAiExposureProxyUrl(String value, {String fallback = '--'}) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return fallback;
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final port = uri.hasPort ? ':${uri.port}' : '';
  if (uri.userInfo.isEmpty) return '${uri.scheme}://$host$port';
  final username = _decodeProxyUriComponent(uri.userInfo.split(':').first);
  return '${uri.scheme}://$username:******@$host$port';
}

String _decodeProxyUriComponent(String value) {
  try {
    return Uri.decodeComponent(value);
  } on FormatException {
    return value;
  }
}

Map<String, Object?> _jsonMap(Object? value) => value is Map
    ? value.map((key, item) => MapEntry('$key', item))
    : <String, Object?>{};

List<String> _stringList(Object? value) => value is List
    ? value.whereType<Object>().map((item) => '$item').toList(growable: false)
    : const <String>[];

List<Object?> _objectList(Object? value) =>
    value is List ? value : const <Object?>[];

String _stringValue(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

bool? _optionalBool(Object? value) => optionalBoolFromValue(value);

bool _boolValue(Object? value, {bool fallback = false}) =>
    _optionalBool(value) ?? fallback;

String? _optionalString(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

DateTime? _optionalDateTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

double? _optionalFiniteDouble(Object? value) {
  return optionalDoubleFromValue(value);
}

int? _optionalNonNegativeInt(Object? value, {int max = 0x1fffffffffffff}) {
  final parsed = optionalIntFromValue(value);
  if (parsed == null) return null;
  return parsed < 0 || parsed > max ? null : parsed;
}

int? _optionalHttpStatus(Object? value) {
  final parsed = _optionalNonNegativeInt(value, max: _kAiExposureMaxHttpStatus);
  return parsed != null && parsed >= _kAiExposureMinHttpStatus ? parsed : null;
}

int _nonNegativeInt(Object? value, {int max = 0x1fffffffffffff}) {
  return (optionalIntFromValue(value) ?? 0).clamp(0, max);
}

int _boundedInt(
  Object? value, {
  required int fallback,
  required int min,
  required int max,
}) {
  return clampedIntFromValue(value, fallback: fallback, min: min, max: max);
}
