import '../../../shared/net/tcp_port_utils.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';

const String webMessagePlatformBuiltinId = 'builtin_web_message_platform';
const String webMessagePlatformBuiltinName = 'Web通用消息平台';

const String webGatewayMetadataKey = 'web_gateway_context';
const String webGatewayDenyAllSelectionMarker = '__openhand_deny_all__';
const int kWebGatewayDefaultListenPort = 8848;
const int kWebGatewayMinListenPort = kTcpPortMin;
const int kWebGatewayMaxListenPort = kTcpPortMax;
const int kWebGatewayDefaultMaxConcurrentRequests = 200;
const int kWebGatewayMinConcurrentRequests = 1;
const int kWebGatewayMaxConcurrentRequests = 5000;
const int kWebGatewayDefaultSingleMessageTokenLimit = 2000;
const int kWebGatewayMinSingleMessageTokenLimit = 64;
const int kWebGatewayMaxSingleMessageTokenLimit = 200000;
const int kWebGatewayDefaultMaxMessagesPerSession = 100;
const int kWebGatewayMinMessagesPerSession = 1;
const int kWebGatewayMaxMessagesPerSession = 10000;
const int kWebGatewayMessageRequestMaxBytes = 24 * kBytesPerMiB;
const int kWebGatewayAttachmentMaxFileBytes = 10 * kBytesPerMiB;
const int kWebGatewayAttachmentMaxTotalBytes = 16 * kBytesPerMiB;
const int kWebGatewayDefaultWorkspaceFileMaxBytes = 1024 * 1024;
const int kWebGatewayMinWorkspaceFileMaxBytes = 1024;
const int kWebGatewayMaxWorkspaceFileMaxBytes = 32 * kBytesPerMiB;
const int kWebGatewayDefaultUploadCacheRetentionDays = 7;
const int kWebGatewayMinUploadCacheRetentionDays = 1;
const int kWebGatewayMaxUploadCacheRetentionDays = 180;
const int kWebGatewayDefaultUploadCacheMaxBytes = 512 * kBytesPerMiB;
const int kWebGatewayMinUploadCacheMaxBytes = 1024 * 1024;
const int kWebGatewayMaxUploadCacheMaxBytes = 10 * kBytesPerGiB;
const int kWebGatewayDefaultHealthTimeoutMs = 3000;
const int kWebGatewayMinHealthTimeoutMs = 250;
const int kWebGatewayMaxHealthTimeoutMs = 60000;
const int kWebGatewayDefaultHealthStatusCode = 200;
const int kWebGatewayMinHealthStatusCode = 100;
const int kWebGatewayMaxHealthStatusCode = 599;
const int kWebGatewayDefaultLogFileMaxBytes = 50 * kBytesPerMiB;
const int kWebGatewayMinLogFileMaxBytes = 1024 * 1024;
const int kWebGatewayMaxLogFileMaxBytes = 512 * kBytesPerMiB;
const int kWebGatewayDefaultLogRotationDays = 7;
const int kWebGatewayMinLogRotationDays = 1;
const int kWebGatewayMaxLogRotationDays = 90;
const int kWebGatewayDefaultLogMaxFiles = 10;
const int kWebGatewayMinLogMaxFiles = 1;
const int kWebGatewayMaxLogMaxFiles = 100;
const int kWebGatewayDefaultLogLazyReadPageSize = 300;
const int kWebGatewayMinLogLazyReadPageSize = 50;
const int kWebGatewayMaxLogLazyReadPageSize = 5000;
const List<String> kWebGatewayDefaultFileLogLevels = <String>[
  'info',
  'warn',
  'error',
  'debug',
];
const Set<String> kWebGatewaySupportedFileLogLevels = <String>{
  'info',
  'success',
  'warn',
  'error',
  'debug',
  'telemetry',
};
const IntValueRange _listenPortRange = IntValueRange(
  fallback: kWebGatewayDefaultListenPort,
  min: kWebGatewayMinListenPort,
  max: kWebGatewayMaxListenPort,
);
const IntValueRange _maxConcurrentRequestsRange = IntValueRange(
  fallback: kWebGatewayDefaultMaxConcurrentRequests,
  min: kWebGatewayMinConcurrentRequests,
  max: kWebGatewayMaxConcurrentRequests,
);
const IntValueRange _singleMessageTokenLimitRange = IntValueRange(
  fallback: kWebGatewayDefaultSingleMessageTokenLimit,
  min: kWebGatewayMinSingleMessageTokenLimit,
  max: kWebGatewayMaxSingleMessageTokenLimit,
);
const IntValueRange _maxMessagesPerSessionRange = IntValueRange(
  fallback: kWebGatewayDefaultMaxMessagesPerSession,
  min: kWebGatewayMinMessagesPerSession,
  max: kWebGatewayMaxMessagesPerSession,
);
const IntValueRange _workspaceFileMaxBytesRange = IntValueRange(
  fallback: kWebGatewayDefaultWorkspaceFileMaxBytes,
  min: kWebGatewayMinWorkspaceFileMaxBytes,
  max: kWebGatewayMaxWorkspaceFileMaxBytes,
);
const IntValueRange _uploadCacheRetentionDaysRange = IntValueRange(
  fallback: kWebGatewayDefaultUploadCacheRetentionDays,
  min: kWebGatewayMinUploadCacheRetentionDays,
  max: kWebGatewayMaxUploadCacheRetentionDays,
);
const IntValueRange _uploadCacheMaxBytesRange = IntValueRange(
  fallback: kWebGatewayDefaultUploadCacheMaxBytes,
  min: kWebGatewayMinUploadCacheMaxBytes,
  max: kWebGatewayMaxUploadCacheMaxBytes,
);
const IntValueRange _healthTimeoutRange = IntValueRange(
  fallback: kWebGatewayDefaultHealthTimeoutMs,
  min: kWebGatewayMinHealthTimeoutMs,
  max: kWebGatewayMaxHealthTimeoutMs,
);
const IntValueRange _healthStatusCodeRange = IntValueRange(
  fallback: kWebGatewayDefaultHealthStatusCode,
  min: kWebGatewayMinHealthStatusCode,
  max: kWebGatewayMaxHealthStatusCode,
);
const IntValueRange _logFileMaxBytesRange = IntValueRange(
  fallback: kWebGatewayDefaultLogFileMaxBytes,
  min: kWebGatewayMinLogFileMaxBytes,
  max: kWebGatewayMaxLogFileMaxBytes,
);
const IntValueRange _logRotationDaysRange = IntValueRange(
  fallback: kWebGatewayDefaultLogRotationDays,
  min: kWebGatewayMinLogRotationDays,
  max: kWebGatewayMaxLogRotationDays,
);
const IntValueRange _logMaxFilesRange = IntValueRange(
  fallback: kWebGatewayDefaultLogMaxFiles,
  min: kWebGatewayMinLogMaxFiles,
  max: kWebGatewayMaxLogMaxFiles,
);
const IntValueRange _logLazyReadPageSizeRange = IntValueRange(
  fallback: kWebGatewayDefaultLogLazyReadPageSize,
  min: kWebGatewayMinLogLazyReadPageSize,
  max: kWebGatewayMaxLogLazyReadPageSize,
);
const Set<String> webGatewayKnowledgeBaseBuiltinToolNames = <String>{
  'KnowledgeSearch',
  'KnowledgeRead',
};
final RegExp _webGatewayWorkspaceExtensionSeparatorPattern = RegExp(
  r'[\n,;；]+',
);
final RegExp _webGatewayWorkspaceExtensionSafeCharsPattern = RegExp(
  r'[^a-z0-9_+-]',
);

bool webGatewayIsDenyAllSelection(List<String> values) {
  return values.contains(webGatewayDenyAllSelectionMarker);
}

bool webGatewayIsKnowledgeBaseBuiltinToolName(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('_', '');
  return normalized == 'knowledgesearch' || normalized == 'knowledgeread';
}

List<String> webGatewayNormalizeWorkspaceFileExtensions(Object? raw) {
  final result = <String>[];
  final seen = <String>{};
  for (final item in stringListFromValue(
    raw,
    separator: _webGatewayWorkspaceExtensionSeparatorPattern,
  )) {
    final normalized = webGatewayNormalizeWorkspaceFileExtension(item);
    if (normalized.isEmpty) continue;
    if (seen.add(normalized)) result.add(normalized);
  }
  return result;
}

String webGatewayNormalizeWorkspaceFileExtension(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  final withoutLeadingDot = trimmed.startsWith('.')
      ? trimmed.substring(1)
      : trimmed;
  final safe = withoutLeadingDot.replaceAll(
    _webGatewayWorkspaceExtensionSafeCharsPattern,
    '',
  );
  return safe.isEmpty ? '' : '.$safe';
}

enum WebGatewayLoginSource {
  webPc('WEB_PC'),
  webMobile('WEB_MOBILE'),
  webTablet('WEB_TABLET'),
  appPc('APP_PC'),
  appMobile('APP_MOBILE'),
  appTablet('APP_TABLET');

  const WebGatewayLoginSource(this.storageValue);

  final String storageValue;

  static WebGatewayLoginSource fromStorage(String? value) {
    return enumByStorageValueOr(
      values,
      value,
      (source) => source.storageValue,
      fallback: WebGatewayLoginSource.webPc,
      normalize: (item) => item.toUpperCase(),
    );
  }
}

enum WebGatewayMessageType {
  text('text'),
  attachment('attachment');

  const WebGatewayMessageType(this.storageValue);

  final String storageValue;

  static WebGatewayMessageType? fromStorage(String? value) {
    return enumByStorageValue(
      values,
      value,
      (type) => type.storageValue,
      normalize: (item) => item.toLowerCase(),
    );
  }
}

enum WebGatewayConversationMode {
  normal('normal'),
  image('image'),
  video('video'),
  audio('audio'),
  deepResearch('deep_research');

  const WebGatewayConversationMode(this.storageValue);

  final String storageValue;

  static WebGatewayConversationMode? fromStorage(String? value) {
    return enumByStorageValue(
      values,
      value,
      (mode) => mode.storageValue,
      normalize: (item) => item.toLowerCase(),
    );
  }
}

class WebGatewayHealthCheckConfig {
  const WebGatewayHealthCheckConfig({
    this.enabled = true,
    this.path = '/api/health',
    this.method = 'GET',
    this.queryParameters = const <String, String>{},
    this.timeoutMs = kWebGatewayDefaultHealthTimeoutMs,
    this.expectedStatusCode = kWebGatewayDefaultHealthStatusCode,
    this.responseContains = 'ok',
    this.followRedirects = false,
  });

  factory WebGatewayHealthCheckConfig.fromJson(Map<String, Object?> json) {
    return WebGatewayHealthCheckConfig(
      enabled: boolFromValue(json['enabled'], defaultValue: true),
      path: _nonEmptyString(json['path'], '/api/health'),
      method: _nonEmptyString(json['method'], 'GET').toUpperCase(),
      queryParameters: _stringMap(json['query_parameters']),
      timeoutMs: _healthTimeoutRange.fromValue(json['timeout_ms']),
      expectedStatusCode: _healthStatusCodeRange.fromValue(
        json['expected_status_code'],
      ),
      responseContains: _stringValue(json['response_contains']).trim(),
      followRedirects: boolFromValue(json['follow_redirects']),
    );
  }

  final bool enabled;
  final String path;
  final String method;
  final Map<String, String> queryParameters;
  final int timeoutMs;
  final int expectedStatusCode;
  final String responseContains;
  final bool followRedirects;

  WebGatewayHealthCheckConfig copyWith({
    bool? enabled,
    String? path,
    String? method,
    Map<String, String>? queryParameters,
    int? timeoutMs,
    int? expectedStatusCode,
    String? responseContains,
    bool? followRedirects,
  }) {
    return WebGatewayHealthCheckConfig(
      enabled: enabled ?? this.enabled,
      path: path ?? this.path,
      method: method ?? this.method,
      queryParameters: queryParameters ?? this.queryParameters,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      expectedStatusCode: expectedStatusCode ?? this.expectedStatusCode,
      responseContains: responseContains ?? this.responseContains,
      followRedirects: followRedirects ?? this.followRedirects,
    );
  }

  WebGatewayHealthCheckConfig normalized() {
    return WebGatewayHealthCheckConfig(
      enabled: enabled,
      path: _nonEmptyString(path, '/api/health'),
      method: _nonEmptyString(method, 'GET').toUpperCase(),
      queryParameters: _stringMap(queryParameters),
      timeoutMs: _healthTimeoutRange.normalize(timeoutMs),
      expectedStatusCode: _healthStatusCodeRange.normalize(expectedStatusCode),
      responseContains: responseContains.trim(),
      followRedirects: followRedirects,
    );
  }

  Map<String, Object?> toJson() {
    final value = normalized();
    return <String, Object?>{
      'enabled': value.enabled,
      'path': value.path,
      'method': value.method,
      'query_parameters': value.queryParameters,
      'timeout_ms': value.timeoutMs,
      'expected_status_code': value.expectedStatusCode,
      'response_contains': value.responseContains,
      'follow_redirects': value.followRedirects,
    };
  }
}

class WebGatewayLogConfig {
  const WebGatewayLogConfig({
    this.fileMaxBytes = kWebGatewayDefaultLogFileMaxBytes,
    this.rotationDays = kWebGatewayDefaultLogRotationDays,
    this.maxFiles = kWebGatewayDefaultLogMaxFiles,
    this.levels = kWebGatewayDefaultFileLogLevels,
    this.lazyReadPageSize = kWebGatewayDefaultLogLazyReadPageSize,
  });

  factory WebGatewayLogConfig.fromJson(Map<String, Object?> json) {
    return WebGatewayLogConfig(
      fileMaxBytes: _logFileMaxBytesRange.fromValue(json['file_max_bytes']),
      rotationDays: _logRotationDaysRange.fromValue(json['rotation_days']),
      maxFiles: _logMaxFilesRange.fromValue(json['max_files']),
      levels: _normalizeFileLogLevels(json['levels']),
      lazyReadPageSize: _logLazyReadPageSizeRange.fromValue(
        json['lazy_read_page_size'],
      ),
    );
  }

  final int fileMaxBytes;
  final int rotationDays;
  final int maxFiles;
  final List<String> levels;
  final int lazyReadPageSize;

  WebGatewayLogConfig copyWith({
    int? fileMaxBytes,
    int? rotationDays,
    int? maxFiles,
    List<String>? levels,
    int? lazyReadPageSize,
  }) {
    return WebGatewayLogConfig(
      fileMaxBytes: fileMaxBytes ?? this.fileMaxBytes,
      rotationDays: rotationDays ?? this.rotationDays,
      maxFiles: maxFiles ?? this.maxFiles,
      levels: levels ?? this.levels,
      lazyReadPageSize: lazyReadPageSize ?? this.lazyReadPageSize,
    );
  }

  WebGatewayLogConfig normalized() {
    return WebGatewayLogConfig(
      fileMaxBytes: _logFileMaxBytesRange.normalize(fileMaxBytes),
      rotationDays: _logRotationDaysRange.normalize(rotationDays),
      maxFiles: _logMaxFilesRange.normalize(maxFiles),
      levels: _normalizeFileLogLevels(levels),
      lazyReadPageSize: _logLazyReadPageSizeRange.normalize(lazyReadPageSize),
    );
  }

  Map<String, Object?> toJson() {
    final value = normalized();
    return <String, Object?>{
      'file_max_bytes': value.fileMaxBytes,
      'rotation_days': value.rotationDays,
      'max_files': value.maxFiles,
      'levels': value.levels,
      'lazy_read_page_size': value.lazyReadPageSize,
    };
  }
}

class WebMessagePlatformConfig {
  const WebMessagePlatformConfig({
    this.enabled = false,
    this.autoStartOnLaunch = true,
    this.autoReloadOnChange = true,
    this.description = defaultDescription,
    this.listenHost = '0.0.0.0',
    this.listenPort = kWebGatewayDefaultListenPort,
    this.authEnabled = false,
    this.username = 'openhand',
    this.password = '',
    this.telemetryEnabled = false,
    this.loggingEnabled = false,
    this.opsEnabled = false,
    this.maxConcurrentRequests = kWebGatewayDefaultMaxConcurrentRequests,
    this.allowedTemplateIds = const <String>[],
    this.allowedSkillNames = const <String>[],
    this.allowedMcpServerNames = const <String>[],
    this.allowedMemoryIds = const <String>[],
    this.allowedBuiltinToolNames = const <String>[],
    this.allowedInstructionIds = const <String>[],
    this.allowedAgentIds = const <String>[],
    this.allowedMessageTypes = const <WebGatewayMessageType>{
      WebGatewayMessageType.text,
      WebGatewayMessageType.attachment,
    },
    this.allowedConversationModes = const <WebGatewayConversationMode>{
      WebGatewayConversationMode.normal,
      WebGatewayConversationMode.image,
      WebGatewayConversationMode.video,
      WebGatewayConversationMode.audio,
    },
    this.allowedModelKeys = const <String>[],
    this.planModeEnabled = false,
    this.agentsEnabled = true,
    this.knowledgeBaseEnabled = true,
    this.readAloudEnabled = true,
    this.translationEnabled = true,
    this.feedbackEnabled = true,
    this.regenerationEnabled = true,
    this.singleMessageTokenLimit = kWebGatewayDefaultSingleMessageTokenLimit,
    this.maxMessagesPerSession = kWebGatewayDefaultMaxMessagesPerSession,
    this.sessionManagementEnabled = true,
    this.workspaceFilesEnabled = true,
    this.workspaceFileWriteEnabled = false,
    this.workspaceFileMaxBytes = kWebGatewayDefaultWorkspaceFileMaxBytes,
    this.workspaceFileAllowedExtensions = const <String>[],
    this.uploadCacheRetentionDays = kWebGatewayDefaultUploadCacheRetentionDays,
    this.uploadCacheMaxBytes = kWebGatewayDefaultUploadCacheMaxBytes,
    this.healthCheck = const WebGatewayHealthCheckConfig(),
    this.logConfig = const WebGatewayLogConfig(),
  });

  factory WebMessagePlatformConfig.fromJson(Map<String, Object?> json) {
    final healthCheckJson = _objectMap(json['health_check']);
    final logConfigJson = _objectMap(json['log_config']);
    return WebMessagePlatformConfig(
      enabled: boolFromValue(json['enabled']),
      autoStartOnLaunch: boolFromValue(
        json['auto_start_on_launch'],
        defaultValue: true,
      ),
      autoReloadOnChange: boolFromValue(
        json['auto_reload_on_change'],
        defaultValue: true,
      ),
      description: _nonEmptyString(json['description'], defaultDescription),
      listenHost: _nonEmptyString(json['listen_host'], '0.0.0.0'),
      listenPort: _listenPortRange.fromValue(json['listen_port']),
      authEnabled: boolFromValue(json['auth_enabled']),
      username: _nonEmptyString(json['username'], 'openhand'),
      password: _stringValue(json['password']),
      telemetryEnabled: boolFromValue(json['telemetry_enabled']),
      loggingEnabled: boolFromValue(json['logging_enabled']),
      opsEnabled: boolFromValue(json['ops_enabled']),
      maxConcurrentRequests: _maxConcurrentRequestsRange.fromValue(
        json['max_concurrent_requests'],
      ),
      allowedTemplateIds: _stringList(json['allowed_template_ids']),
      allowedSkillNames: _stringList(json['allowed_skill_names']),
      allowedMcpServerNames: _stringList(json['allowed_mcp_server_names']),
      allowedMemoryIds: _stringList(json['allowed_memory_ids']),
      allowedBuiltinToolNames: _stringList(json['allowed_builtin_tool_names']),
      allowedInstructionIds: _stringList(json['allowed_instruction_ids']),
      allowedAgentIds: _stringList(json['allowed_agent_ids']),
      allowedMessageTypes: _enumSet(
        json['allowed_message_types'],
        WebGatewayMessageType.fromStorage,
        const <WebGatewayMessageType>{
          WebGatewayMessageType.text,
          WebGatewayMessageType.attachment,
        },
      ),
      allowedConversationModes: _enumSet(
        json['allowed_conversation_modes'],
        WebGatewayConversationMode.fromStorage,
        const <WebGatewayConversationMode>{
          WebGatewayConversationMode.normal,
          WebGatewayConversationMode.image,
          WebGatewayConversationMode.video,
          WebGatewayConversationMode.audio,
        },
      ),
      allowedModelKeys: _stringList(json['allowed_model_keys']),
      planModeEnabled: boolFromValue(json['plan_mode_enabled']),
      agentsEnabled: boolFromValue(json['agents_enabled'], defaultValue: true),
      knowledgeBaseEnabled: boolFromValue(
        json['knowledge_base_enabled'],
        defaultValue: true,
      ),
      readAloudEnabled: boolFromValue(
        json['read_aloud_enabled'],
        defaultValue: true,
      ),
      translationEnabled: boolFromValue(
        json['translation_enabled'],
        defaultValue: true,
      ),
      feedbackEnabled: boolFromValue(
        json['feedback_enabled'],
        defaultValue: true,
      ),
      regenerationEnabled: boolFromValue(
        json['regeneration_enabled'],
        defaultValue: true,
      ),
      singleMessageTokenLimit: _singleMessageTokenLimitRange.fromValue(
        json['single_message_token_limit'],
      ),
      maxMessagesPerSession: _maxMessagesPerSessionRange.fromValue(
        json['max_messages_per_session'],
      ),
      sessionManagementEnabled: boolFromValue(
        json['session_management_enabled'],
        defaultValue: true,
      ),
      workspaceFilesEnabled: boolFromValue(
        json['workspace_files_enabled'],
        defaultValue: true,
      ),
      workspaceFileWriteEnabled: boolFromValue(
        json['workspace_file_write_enabled'],
      ),
      workspaceFileMaxBytes: _workspaceFileMaxBytesRange.fromValue(
        json['workspace_file_max_bytes'],
      ),
      workspaceFileAllowedExtensions:
          webGatewayNormalizeWorkspaceFileExtensions(
            json['workspace_file_allowed_extensions'],
          ),
      uploadCacheRetentionDays: _uploadCacheRetentionDaysRange.fromValue(
        json['upload_cache_retention_days'],
      ),
      uploadCacheMaxBytes: _uploadCacheMaxBytesRange.fromValue(
        json['upload_cache_max_bytes'],
      ),
      healthCheck: healthCheckJson.isEmpty
          ? const WebGatewayHealthCheckConfig()
          : WebGatewayHealthCheckConfig.fromJson(healthCheckJson),
      logConfig: logConfigJson.isEmpty
          ? const WebGatewayLogConfig()
          : WebGatewayLogConfig.fromJson(logConfigJson),
    );
  }

  static const String defaultDescription =
      'OpenHand 内建的 Web 通用消息平台服务。它把本机 OpenHand 会话、安全策略、模型能力、MCP、技能、记忆和内建工具以受控 Web API 与响应式聊天页面开放给可信设备使用，适合在 PC、手机和平板上继续同一组线程会话。';

  final bool enabled;
  final bool autoStartOnLaunch;
  final bool autoReloadOnChange;
  final String description;
  final String listenHost;
  final int listenPort;
  final bool authEnabled;
  final String username;
  final String password;
  final bool telemetryEnabled;
  final bool loggingEnabled;
  final bool opsEnabled;
  final int maxConcurrentRequests;
  final List<String> allowedTemplateIds;
  final List<String> allowedSkillNames;
  final List<String> allowedMcpServerNames;
  final List<String> allowedMemoryIds;
  final List<String> allowedBuiltinToolNames;
  final List<String> allowedInstructionIds;
  final List<String> allowedAgentIds;
  final Set<WebGatewayMessageType> allowedMessageTypes;
  final Set<WebGatewayConversationMode> allowedConversationModes;
  final List<String> allowedModelKeys;
  final bool planModeEnabled;
  final bool agentsEnabled;
  final bool knowledgeBaseEnabled;
  final bool readAloudEnabled;
  final bool translationEnabled;
  final bool feedbackEnabled;
  final bool regenerationEnabled;
  final int singleMessageTokenLimit;
  final int maxMessagesPerSession;
  final bool sessionManagementEnabled;
  final bool workspaceFilesEnabled;
  final bool workspaceFileWriteEnabled;
  final int workspaceFileMaxBytes;
  final List<String> workspaceFileAllowedExtensions;
  final int uploadCacheRetentionDays;
  final int uploadCacheMaxBytes;
  final WebGatewayHealthCheckConfig healthCheck;
  final WebGatewayLogConfig logConfig;

  String get endpointUrl => 'http://$listenHost:$listenPort';

  WebMessagePlatformConfig copyWith({
    bool? enabled,
    bool? autoStartOnLaunch,
    bool? autoReloadOnChange,
    String? description,
    String? listenHost,
    int? listenPort,
    bool? authEnabled,
    String? username,
    String? password,
    bool? telemetryEnabled,
    bool? loggingEnabled,
    bool? opsEnabled,
    int? maxConcurrentRequests,
    List<String>? allowedTemplateIds,
    List<String>? allowedSkillNames,
    List<String>? allowedMcpServerNames,
    List<String>? allowedMemoryIds,
    List<String>? allowedBuiltinToolNames,
    List<String>? allowedInstructionIds,
    List<String>? allowedAgentIds,
    Set<WebGatewayMessageType>? allowedMessageTypes,
    Set<WebGatewayConversationMode>? allowedConversationModes,
    List<String>? allowedModelKeys,
    bool? planModeEnabled,
    bool? agentsEnabled,
    bool? knowledgeBaseEnabled,
    bool? readAloudEnabled,
    bool? translationEnabled,
    bool? feedbackEnabled,
    bool? regenerationEnabled,
    int? singleMessageTokenLimit,
    int? maxMessagesPerSession,
    bool? sessionManagementEnabled,
    bool? workspaceFilesEnabled,
    bool? workspaceFileWriteEnabled,
    int? workspaceFileMaxBytes,
    List<String>? workspaceFileAllowedExtensions,
    int? uploadCacheRetentionDays,
    int? uploadCacheMaxBytes,
    WebGatewayHealthCheckConfig? healthCheck,
    WebGatewayLogConfig? logConfig,
  }) {
    return WebMessagePlatformConfig(
      enabled: enabled ?? this.enabled,
      autoStartOnLaunch: autoStartOnLaunch ?? this.autoStartOnLaunch,
      autoReloadOnChange: autoReloadOnChange ?? this.autoReloadOnChange,
      description: description ?? this.description,
      listenHost: listenHost ?? this.listenHost,
      listenPort: listenPort ?? this.listenPort,
      authEnabled: authEnabled ?? this.authEnabled,
      username: username ?? this.username,
      password: password ?? this.password,
      telemetryEnabled: telemetryEnabled ?? this.telemetryEnabled,
      loggingEnabled: loggingEnabled ?? this.loggingEnabled,
      opsEnabled: opsEnabled ?? this.opsEnabled,
      maxConcurrentRequests:
          maxConcurrentRequests ?? this.maxConcurrentRequests,
      allowedTemplateIds: allowedTemplateIds ?? this.allowedTemplateIds,
      allowedSkillNames: allowedSkillNames ?? this.allowedSkillNames,
      allowedMcpServerNames:
          allowedMcpServerNames ?? this.allowedMcpServerNames,
      allowedMemoryIds: allowedMemoryIds ?? this.allowedMemoryIds,
      allowedBuiltinToolNames:
          allowedBuiltinToolNames ?? this.allowedBuiltinToolNames,
      allowedInstructionIds:
          allowedInstructionIds ?? this.allowedInstructionIds,
      allowedAgentIds: allowedAgentIds ?? this.allowedAgentIds,
      allowedMessageTypes: allowedMessageTypes ?? this.allowedMessageTypes,
      allowedConversationModes:
          allowedConversationModes ?? this.allowedConversationModes,
      allowedModelKeys: allowedModelKeys ?? this.allowedModelKeys,
      planModeEnabled: planModeEnabled ?? this.planModeEnabled,
      agentsEnabled: agentsEnabled ?? this.agentsEnabled,
      knowledgeBaseEnabled: knowledgeBaseEnabled ?? this.knowledgeBaseEnabled,
      readAloudEnabled: readAloudEnabled ?? this.readAloudEnabled,
      translationEnabled: translationEnabled ?? this.translationEnabled,
      feedbackEnabled: feedbackEnabled ?? this.feedbackEnabled,
      regenerationEnabled: regenerationEnabled ?? this.regenerationEnabled,
      singleMessageTokenLimit:
          singleMessageTokenLimit ?? this.singleMessageTokenLimit,
      maxMessagesPerSession:
          maxMessagesPerSession ?? this.maxMessagesPerSession,
      sessionManagementEnabled:
          sessionManagementEnabled ?? this.sessionManagementEnabled,
      workspaceFilesEnabled:
          workspaceFilesEnabled ?? this.workspaceFilesEnabled,
      workspaceFileWriteEnabled:
          workspaceFileWriteEnabled ?? this.workspaceFileWriteEnabled,
      workspaceFileMaxBytes:
          workspaceFileMaxBytes ?? this.workspaceFileMaxBytes,
      workspaceFileAllowedExtensions:
          workspaceFileAllowedExtensions ?? this.workspaceFileAllowedExtensions,
      uploadCacheRetentionDays:
          uploadCacheRetentionDays ?? this.uploadCacheRetentionDays,
      uploadCacheMaxBytes: uploadCacheMaxBytes ?? this.uploadCacheMaxBytes,
      healthCheck: healthCheck ?? this.healthCheck,
      logConfig: logConfig ?? this.logConfig,
    );
  }

  WebMessagePlatformConfig normalized() {
    return WebMessagePlatformConfig(
      enabled: enabled,
      autoStartOnLaunch: autoStartOnLaunch,
      autoReloadOnChange: autoReloadOnChange,
      description: _nonEmptyString(description, defaultDescription),
      listenHost: _nonEmptyString(listenHost, '0.0.0.0'),
      listenPort: clampIntToRange(
        listenPort,
        min: kWebGatewayMinListenPort,
        max: kWebGatewayMaxListenPort,
      ),
      authEnabled: authEnabled,
      username: _nonEmptyString(username, 'openhand'),
      password: password,
      telemetryEnabled: telemetryEnabled,
      loggingEnabled: loggingEnabled,
      opsEnabled: opsEnabled,
      maxConcurrentRequests: clampIntToRange(
        maxConcurrentRequests,
        min: kWebGatewayMinConcurrentRequests,
        max: kWebGatewayMaxConcurrentRequests,
      ),
      allowedTemplateIds: _stringList(allowedTemplateIds),
      allowedSkillNames: _stringList(allowedSkillNames),
      allowedMcpServerNames: _stringList(allowedMcpServerNames),
      allowedMemoryIds: _stringList(allowedMemoryIds),
      allowedBuiltinToolNames: _stringList(allowedBuiltinToolNames),
      allowedInstructionIds: _stringList(allowedInstructionIds),
      allowedAgentIds: _stringList(allowedAgentIds),
      allowedMessageTypes: allowedMessageTypes,
      allowedConversationModes: allowedConversationModes,
      allowedModelKeys: _stringList(allowedModelKeys),
      planModeEnabled: planModeEnabled,
      agentsEnabled: agentsEnabled,
      knowledgeBaseEnabled: knowledgeBaseEnabled,
      readAloudEnabled: readAloudEnabled,
      translationEnabled: translationEnabled,
      feedbackEnabled: feedbackEnabled,
      regenerationEnabled: regenerationEnabled,
      singleMessageTokenLimit: clampIntToRange(
        singleMessageTokenLimit,
        min: kWebGatewayMinSingleMessageTokenLimit,
        max: kWebGatewayMaxSingleMessageTokenLimit,
      ),
      maxMessagesPerSession: clampIntToRange(
        maxMessagesPerSession,
        min: kWebGatewayMinMessagesPerSession,
        max: kWebGatewayMaxMessagesPerSession,
      ),
      sessionManagementEnabled: sessionManagementEnabled,
      workspaceFilesEnabled: workspaceFilesEnabled,
      workspaceFileWriteEnabled: workspaceFileWriteEnabled,
      workspaceFileMaxBytes: clampIntToRange(
        workspaceFileMaxBytes,
        min: kWebGatewayMinWorkspaceFileMaxBytes,
        max: kWebGatewayMaxWorkspaceFileMaxBytes,
      ),
      workspaceFileAllowedExtensions:
          webGatewayNormalizeWorkspaceFileExtensions(
            workspaceFileAllowedExtensions,
          ),
      uploadCacheRetentionDays: clampIntToRange(
        uploadCacheRetentionDays,
        min: kWebGatewayMinUploadCacheRetentionDays,
        max: kWebGatewayMaxUploadCacheRetentionDays,
      ),
      uploadCacheMaxBytes: clampIntToRange(
        uploadCacheMaxBytes,
        min: kWebGatewayMinUploadCacheMaxBytes,
        max: kWebGatewayMaxUploadCacheMaxBytes,
      ),
      healthCheck: healthCheck.normalized(),
      logConfig: logConfig.normalized(),
    );
  }

  Map<String, Object?> toJson() {
    final value = normalized();
    return <String, Object?>{
      'id': webMessagePlatformBuiltinId,
      'name': webMessagePlatformBuiltinName,
      'enabled': value.enabled,
      'auto_start_on_launch': value.autoStartOnLaunch,
      'auto_reload_on_change': value.autoReloadOnChange,
      'description': value.description,
      'listen_host': value.listenHost,
      'listen_port': value.listenPort,
      'auth_enabled': value.authEnabled,
      'username': value.username,
      'password': value.password,
      'telemetry_enabled': value.telemetryEnabled,
      'logging_enabled': value.loggingEnabled,
      'ops_enabled': value.opsEnabled,
      'max_concurrent_requests': value.maxConcurrentRequests,
      'allowed_template_ids': value.allowedTemplateIds,
      'allowed_skill_names': value.allowedSkillNames,
      'allowed_mcp_server_names': value.allowedMcpServerNames,
      'allowed_memory_ids': value.allowedMemoryIds,
      'allowed_builtin_tool_names': value.allowedBuiltinToolNames,
      'allowed_instruction_ids': value.allowedInstructionIds,
      'allowed_agent_ids': value.allowedAgentIds,
      'allowed_message_types': value.allowedMessageTypes
          .map((item) => item.storageValue)
          .toList(growable: false),
      'allowed_conversation_modes': value.allowedConversationModes
          .map((item) => item.storageValue)
          .toList(growable: false),
      'allowed_model_keys': value.allowedModelKeys,
      'plan_mode_enabled': value.planModeEnabled,
      'agents_enabled': value.agentsEnabled,
      'knowledge_base_enabled': value.knowledgeBaseEnabled,
      'read_aloud_enabled': value.readAloudEnabled,
      'translation_enabled': value.translationEnabled,
      'feedback_enabled': value.feedbackEnabled,
      'regeneration_enabled': value.regenerationEnabled,
      'single_message_token_limit': value.singleMessageTokenLimit,
      'max_messages_per_session': value.maxMessagesPerSession,
      'session_management_enabled': value.sessionManagementEnabled,
      'workspace_files_enabled': value.workspaceFilesEnabled,
      'workspace_file_write_enabled': value.workspaceFileWriteEnabled,
      'workspace_file_max_bytes': value.workspaceFileMaxBytes,
      'workspace_file_allowed_extensions': value.workspaceFileAllowedExtensions,
      'upload_cache_retention_days': value.uploadCacheRetentionDays,
      'upload_cache_max_bytes': value.uploadCacheMaxBytes,
      'health_check': value.healthCheck.toJson(),
      'log_config': value.logConfig.toJson(),
    };
  }
}

String _stringValue(Object? value) => value == null ? '' : '$value';

String _nonEmptyString(Object? value, String fallback) {
  final text = _stringValue(value).trim();
  return text.isEmpty ? fallback : text;
}

List<String> _stringList(
  Object? raw, {
  List<String> fallback = const <String>[],
}) {
  final parsed = stringListFromValue(raw);
  if (parsed.isEmpty && raw is! List) {
    return List<String>.from(fallback);
  }
  final seen = <String>{};
  final values = <String>[];
  for (final text in parsed) {
    if (seen.add(text.toLowerCase())) values.add(text);
  }
  return values;
}

List<String> _normalizeFileLogLevels(Object? raw) {
  return _stringList(raw, fallback: kWebGatewayDefaultFileLogLevels)
      .map((level) => level.toLowerCase())
      .where(kWebGatewaySupportedFileLogLevels.contains)
      .toList(growable: false);
}

Map<String, String> _stringMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final result = <String, String>{};
  raw.forEach((key, value) {
    if (value == null) return;
    final k = '$key'.trim();
    final v = '$value'.trim();
    if (k.isNotEmpty) result[k] = v;
  });
  return result;
}

Map<String, Object?> _objectMap(Object? raw) {
  if (raw is! Map) return const <String, Object?>{};
  return stringKeyedMapFromValue(raw);
}

Set<T> _enumSet<T>(Object? raw, T? Function(String?) parser, Set<T> fallback) {
  if (raw is! List) return Set<T>.from(fallback);
  if (raw.isEmpty) return <T>{};
  final result = <T>{};
  for (final item in raw) {
    final parsed = parser('$item');
    if (parsed != null) result.add(parsed);
  }
  return result.isEmpty ? Set<T>.from(fallback) : result;
}
