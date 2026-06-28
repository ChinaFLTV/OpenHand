import '../../../shared/util/input_value_parsing.dart';

const String webMessagePlatformBuiltinId = 'builtin_web_message_platform';
const String webMessagePlatformBuiltinName = 'Web通用消息平台';

const String webGatewayMetadataKey = 'web_gateway_context';
const String webGatewayLoginSourceKey = 'login_source';
const String webGatewayDeviceIdKey = 'device_id';
const String webGatewayDeviceMacKey = 'device_mac_address';
const String webGatewayDenyAllSelectionMarker = '__openhand_deny_all__';

bool webGatewayIsDenyAllSelection(List<String> values) {
  return values.contains(webGatewayDenyAllSelectionMarker);
}

enum WebGatewayLoginSource {
  webPc('WEB_PC'),
  webMobile('WEB_MOBILE'),
  appPc('APP_PC'),
  appMobile('APP_MOBILE'),
  appTablet('APP_TABLET');

  const WebGatewayLoginSource(this.storageValue);

  final String storageValue;

  static WebGatewayLoginSource fromStorage(String? value) {
    final normalized = value?.trim().toUpperCase() ?? '';
    return WebGatewayLoginSource.values.firstWhere(
      (item) => item.storageValue == normalized,
      orElse: () => WebGatewayLoginSource.webPc,
    );
  }
}

enum WebGatewayMessageType {
  text('text'),
  attachment('attachment');

  const WebGatewayMessageType(this.storageValue);

  final String storageValue;

  static WebGatewayMessageType? fromStorage(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    for (final item in values) {
      if (item.storageValue == normalized) return item;
    }
    return null;
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
    final normalized = value?.trim().toLowerCase() ?? '';
    for (final item in values) {
      if (item.storageValue == normalized) return item;
    }
    return null;
  }
}

class WebGatewayHealthCheckConfig {
  const WebGatewayHealthCheckConfig({
    this.enabled = true,
    this.path = '/api/health',
    this.method = 'GET',
    this.queryParameters = const <String, String>{},
    this.timeoutMs = 3000,
    this.expectedStatusCode = 200,
    this.responseContains = 'ok',
    this.followRedirects = false,
  });

  factory WebGatewayHealthCheckConfig.fromJson(Map<String, Object?> json) {
    return WebGatewayHealthCheckConfig(
      enabled: boolFromValue(json['enabled'], defaultValue: true),
      path: _nonEmptyString(json['path'], '/api/health'),
      method: _nonEmptyString(json['method'], 'GET').toUpperCase(),
      queryParameters: _stringMap(json['query_parameters']),
      timeoutMs: clampedIntFromValue(
        json['timeout_ms'],
        fallback: 3000,
        min: 250,
        max: 60000,
      ),
      expectedStatusCode: clampedIntFromValue(
        json['expected_status_code'],
        fallback: 200,
        min: 100,
        max: 599,
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'path': path,
      'method': method,
      'query_parameters': queryParameters,
      'timeout_ms': timeoutMs,
      'expected_status_code': expectedStatusCode,
      'response_contains': responseContains,
      'follow_redirects': followRedirects,
    };
  }
}

class WebGatewayLogConfig {
  const WebGatewayLogConfig({
    this.fileMaxBytes = 50 * 1024 * 1024,
    this.rotationDays = 7,
    this.maxFiles = 10,
    this.levels = const <String>['info', 'warn', 'error', 'debug'],
    this.lazyReadPageSize = 300,
  });

  factory WebGatewayLogConfig.fromJson(Map<String, Object?> json) {
    return WebGatewayLogConfig(
      fileMaxBytes: clampedIntFromValue(
        json['file_max_bytes'],
        fallback: 50 * 1024 * 1024,
        min: 1024 * 1024,
        max: 512 * 1024 * 1024,
      ),
      rotationDays: clampedIntFromValue(
        json['rotation_days'],
        fallback: 7,
        min: 1,
        max: 90,
      ),
      maxFiles: clampedIntFromValue(
        json['max_files'],
        fallback: 10,
        min: 1,
        max: 100,
      ),
      levels: _stringList(
        json['levels'],
        fallback: const <String>['info', 'warn', 'error', 'debug'],
      ),
      lazyReadPageSize: clampedIntFromValue(
        json['lazy_read_page_size'],
        fallback: 300,
        min: 50,
        max: 5000,
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'file_max_bytes': fileMaxBytes,
      'rotation_days': rotationDays,
      'max_files': maxFiles,
      'levels': levels,
      'lazy_read_page_size': lazyReadPageSize,
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
    this.listenPort = 8848,
    this.authEnabled = false,
    this.username = 'openhand',
    this.password = '',
    this.telemetryEnabled = false,
    this.loggingEnabled = false,
    this.opsEnabled = false,
    this.maxConcurrentRequests = 200,
    this.allowedTemplateIds = const <String>[],
    this.allowedSkillNames = const <String>[],
    this.allowedMcpServerNames = const <String>[],
    this.allowedMemoryIds = const <String>[],
    this.allowedBuiltinToolNames = const <String>[],
    this.allowedInstructionIds = const <String>[],
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
    this.readAloudEnabled = true,
    this.translationEnabled = true,
    this.feedbackEnabled = true,
    this.regenerationEnabled = true,
    this.singleMessageTokenLimit = 2000,
    this.maxMessagesPerSession = 100,
    this.sessionManagementEnabled = true,
    this.workspaceFilesEnabled = true,
    this.workspaceFileWriteEnabled = false,
    this.workspaceFileMaxBytes = 1024 * 1024,
    this.workspaceFileAllowedExtensions = const <String>[],
    this.uploadCacheRetentionDays = 7,
    this.uploadCacheMaxBytes = 512 * 1024 * 1024,
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
      listenPort: clampedIntFromValue(
        json['listen_port'],
        fallback: 8848,
        min: 1,
        max: 65535,
      ),
      authEnabled: boolFromValue(json['auth_enabled']),
      username: _nonEmptyString(json['username'], 'openhand'),
      password: _stringValue(json['password']),
      telemetryEnabled: boolFromValue(json['telemetry_enabled']),
      loggingEnabled: boolFromValue(json['logging_enabled']),
      opsEnabled: boolFromValue(json['ops_enabled']),
      maxConcurrentRequests: clampedIntFromValue(
        json['max_concurrent_requests'],
        fallback: 200,
        min: 1,
        max: 5000,
      ),
      allowedTemplateIds: _stringList(json['allowed_template_ids']),
      allowedSkillNames: _stringList(json['allowed_skill_names']),
      allowedMcpServerNames: _stringList(json['allowed_mcp_server_names']),
      allowedMemoryIds: _stringList(json['allowed_memory_ids']),
      allowedBuiltinToolNames: _stringList(json['allowed_builtin_tool_names']),
      allowedInstructionIds: _stringList(json['allowed_instruction_ids']),
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
      singleMessageTokenLimit: clampedIntFromValue(
        json['single_message_token_limit'],
        fallback: 2000,
        min: 64,
        max: 200000,
      ),
      maxMessagesPerSession: clampedIntFromValue(
        json['max_messages_per_session'],
        fallback: 100,
        min: 1,
        max: 10000,
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
      workspaceFileMaxBytes: clampedIntFromValue(
        json['workspace_file_max_bytes'],
        fallback: 1024 * 1024,
        min: 1024,
        max: 32 * 1024 * 1024,
      ),
      workspaceFileAllowedExtensions: _extensionList(
        json['workspace_file_allowed_extensions'],
      ),
      uploadCacheRetentionDays: clampedIntFromValue(
        json['upload_cache_retention_days'],
        fallback: 7,
        min: 1,
        max: 180,
      ),
      uploadCacheMaxBytes: clampedIntFromValue(
        json['upload_cache_max_bytes'],
        fallback: 512 * 1024 * 1024,
        min: 1024 * 1024,
        max: 10 * 1024 * 1024 * 1024,
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
  final Set<WebGatewayMessageType> allowedMessageTypes;
  final Set<WebGatewayConversationMode> allowedConversationModes;
  final List<String> allowedModelKeys;
  final bool planModeEnabled;
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
    Set<WebGatewayMessageType>? allowedMessageTypes,
    Set<WebGatewayConversationMode>? allowedConversationModes,
    List<String>? allowedModelKeys,
    bool? planModeEnabled,
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
      allowedMessageTypes: allowedMessageTypes ?? this.allowedMessageTypes,
      allowedConversationModes:
          allowedConversationModes ?? this.allowedConversationModes,
      allowedModelKeys: allowedModelKeys ?? this.allowedModelKeys,
      planModeEnabled: planModeEnabled ?? this.planModeEnabled,
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': webMessagePlatformBuiltinId,
      'name': webMessagePlatformBuiltinName,
      'enabled': enabled,
      'auto_start_on_launch': autoStartOnLaunch,
      'auto_reload_on_change': autoReloadOnChange,
      'description': description,
      'listen_host': listenHost,
      'listen_port': listenPort,
      'auth_enabled': authEnabled,
      'username': username,
      'password': password,
      'telemetry_enabled': telemetryEnabled,
      'logging_enabled': loggingEnabled,
      'ops_enabled': opsEnabled,
      'max_concurrent_requests': maxConcurrentRequests,
      'allowed_template_ids': allowedTemplateIds,
      'allowed_skill_names': allowedSkillNames,
      'allowed_mcp_server_names': allowedMcpServerNames,
      'allowed_memory_ids': allowedMemoryIds,
      'allowed_builtin_tool_names': allowedBuiltinToolNames,
      'allowed_instruction_ids': allowedInstructionIds,
      'allowed_message_types': allowedMessageTypes
          .map((item) => item.storageValue)
          .toList(growable: false),
      'allowed_conversation_modes': allowedConversationModes
          .map((item) => item.storageValue)
          .toList(growable: false),
      'allowed_model_keys': allowedModelKeys,
      'plan_mode_enabled': planModeEnabled,
      'read_aloud_enabled': readAloudEnabled,
      'translation_enabled': translationEnabled,
      'feedback_enabled': feedbackEnabled,
      'regeneration_enabled': regenerationEnabled,
      'single_message_token_limit': singleMessageTokenLimit,
      'max_messages_per_session': maxMessagesPerSession,
      'session_management_enabled': sessionManagementEnabled,
      'workspace_files_enabled': workspaceFilesEnabled,
      'workspace_file_write_enabled': workspaceFileWriteEnabled,
      'workspace_file_max_bytes': workspaceFileMaxBytes,
      'workspace_file_allowed_extensions': workspaceFileAllowedExtensions,
      'upload_cache_retention_days': uploadCacheRetentionDays,
      'upload_cache_max_bytes': uploadCacheMaxBytes,
      'health_check': healthCheck.toJson(),
      'log_config': logConfig.toJson(),
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

List<String> _extensionList(Object? raw) {
  final result = <String>[];
  final seen = <String>{};
  for (final item in _stringList(raw)) {
    final normalized = _normalizeExtension(item);
    if (normalized.isEmpty) continue;
    if (seen.add(normalized)) result.add(normalized);
  }
  return result;
}

String _normalizeExtension(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  final withoutLeadingDot = trimmed.startsWith('.')
      ? trimmed.substring(1)
      : trimmed;
  final safe = withoutLeadingDot.replaceAll(RegExp(r'[^a-z0-9_+-]'), '');
  return safe.isEmpty ? '' : '.$safe';
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
