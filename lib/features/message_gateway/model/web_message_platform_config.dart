import 'dart:math' as math;

const String webMessagePlatformBuiltinId = 'builtin_web_message_platform';
const String webMessagePlatformBuiltinName = 'Web通用消息平台';

const String webGatewayMetadataKey = 'web_gateway_context';
const String webGatewayLoginSourceKey = 'login_source';
const String webGatewayDeviceIdKey = 'device_id';
const String webGatewayDeviceMacKey = 'device_mac_address';

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
      enabled: json['enabled'] as bool? ?? true,
      path: _nonEmptyString(json['path'], '/api/health'),
      method: _nonEmptyString(json['method'], 'GET').toUpperCase(),
      queryParameters: _stringMap(json['query_parameters']),
      timeoutMs: _clampInt(json['timeout_ms'], 3000, 250, 60000),
      expectedStatusCode: _clampInt(
        json['expected_status_code'],
        200,
        100,
        599,
      ),
      responseContains: _stringValue(json['response_contains']).trim(),
      followRedirects: json['follow_redirects'] as bool? ?? false,
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
      fileMaxBytes: _clampInt(
        json['file_max_bytes'],
        50 * 1024 * 1024,
        1024 * 1024,
        512 * 1024 * 1024,
      ),
      rotationDays: _clampInt(json['rotation_days'], 7, 1, 90),
      maxFiles: _clampInt(json['max_files'], 10, 1, 100),
      levels: _stringList(
        json['levels'],
        fallback: const <String>['info', 'warn', 'error', 'debug'],
      ),
      lazyReadPageSize: _clampInt(json['lazy_read_page_size'], 300, 50, 5000),
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
    this.singleMessageTokenLimit = 2000,
    this.maxMessagesPerSession = 100,
    this.sessionManagementEnabled = true,
    this.workspaceFilesEnabled = true,
    this.workspaceFileWriteEnabled = true,
    this.workspaceFileMaxBytes = 1024 * 1024,
    this.workspaceFileAllowedExtensions = const <String>[],
    this.uploadCacheRetentionDays = 7,
    this.healthCheck = const WebGatewayHealthCheckConfig(),
    this.logConfig = const WebGatewayLogConfig(),
  });

  factory WebMessagePlatformConfig.fromJson(Map<String, Object?> json) {
    return WebMessagePlatformConfig(
      enabled: json['enabled'] as bool? ?? false,
      description: _nonEmptyString(json['description'], defaultDescription),
      listenHost: _nonEmptyString(json['listen_host'], '0.0.0.0'),
      listenPort: _clampInt(json['listen_port'], 8848, 1, 65535),
      authEnabled: json['auth_enabled'] as bool? ?? false,
      username: _nonEmptyString(json['username'], 'openhand'),
      password: _stringValue(json['password']),
      telemetryEnabled: json['telemetry_enabled'] as bool? ?? false,
      loggingEnabled: json['logging_enabled'] as bool? ?? false,
      opsEnabled: json['ops_enabled'] as bool? ?? false,
      maxConcurrentRequests: _clampInt(
        json['max_concurrent_requests'],
        200,
        1,
        5000,
      ),
      allowedTemplateIds: _stringList(json['allowed_template_ids']),
      allowedSkillNames: _stringList(json['allowed_skill_names']),
      allowedMcpServerNames: _stringList(json['allowed_mcp_server_names']),
      allowedMemoryIds: _stringList(json['allowed_memory_ids']),
      allowedBuiltinToolNames: _stringList(json['allowed_builtin_tool_names']),
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
      planModeEnabled: json['plan_mode_enabled'] as bool? ?? false,
      singleMessageTokenLimit: _clampInt(
        json['single_message_token_limit'],
        2000,
        64,
        200000,
      ),
      maxMessagesPerSession: _clampInt(
        json['max_messages_per_session'],
        100,
        1,
        10000,
      ),
      sessionManagementEnabled:
          json['session_management_enabled'] as bool? ?? true,
      workspaceFilesEnabled: json['workspace_files_enabled'] as bool? ?? true,
      workspaceFileWriteEnabled:
          json['workspace_file_write_enabled'] as bool? ?? true,
      workspaceFileMaxBytes: _clampInt(
        json['workspace_file_max_bytes'],
        1024 * 1024,
        1024,
        32 * 1024 * 1024,
      ),
      workspaceFileAllowedExtensions: _extensionList(
        json['workspace_file_allowed_extensions'],
      ),
      uploadCacheRetentionDays: _clampInt(
        json['upload_cache_retention_days'],
        7,
        1,
        180,
      ),
      healthCheck: json['health_check'] is Map
          ? WebGatewayHealthCheckConfig.fromJson(
              Map<String, Object?>.from(json['health_check'] as Map),
            )
          : const WebGatewayHealthCheckConfig(),
      logConfig: json['log_config'] is Map
          ? WebGatewayLogConfig.fromJson(
              Map<String, Object?>.from(json['log_config'] as Map),
            )
          : const WebGatewayLogConfig(),
    );
  }

  static const String defaultDescription =
      'OpenHand 内建的 Web 通用消息平台服务。它把本机 OpenHand 会话、安全策略、模型能力、MCP、技能、记忆和内建工具以受控 Web API 与响应式聊天页面开放给可信设备使用，适合在 PC、手机和平板上继续同一组线程会话。';

  final bool enabled;
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
  final Set<WebGatewayMessageType> allowedMessageTypes;
  final Set<WebGatewayConversationMode> allowedConversationModes;
  final List<String> allowedModelKeys;
  final bool planModeEnabled;
  final int singleMessageTokenLimit;
  final int maxMessagesPerSession;
  final bool sessionManagementEnabled;
  final bool workspaceFilesEnabled;
  final bool workspaceFileWriteEnabled;
  final int workspaceFileMaxBytes;
  final List<String> workspaceFileAllowedExtensions;
  final int uploadCacheRetentionDays;
  final WebGatewayHealthCheckConfig healthCheck;
  final WebGatewayLogConfig logConfig;

  String get endpointUrl => 'http://$listenHost:$listenPort';

  WebMessagePlatformConfig copyWith({
    bool? enabled,
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
    Set<WebGatewayMessageType>? allowedMessageTypes,
    Set<WebGatewayConversationMode>? allowedConversationModes,
    List<String>? allowedModelKeys,
    bool? planModeEnabled,
    int? singleMessageTokenLimit,
    int? maxMessagesPerSession,
    bool? sessionManagementEnabled,
    bool? workspaceFilesEnabled,
    bool? workspaceFileWriteEnabled,
    int? workspaceFileMaxBytes,
    List<String>? workspaceFileAllowedExtensions,
    int? uploadCacheRetentionDays,
    WebGatewayHealthCheckConfig? healthCheck,
    WebGatewayLogConfig? logConfig,
  }) {
    return WebMessagePlatformConfig(
      enabled: enabled ?? this.enabled,
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
      allowedMessageTypes: allowedMessageTypes ?? this.allowedMessageTypes,
      allowedConversationModes:
          allowedConversationModes ?? this.allowedConversationModes,
      allowedModelKeys: allowedModelKeys ?? this.allowedModelKeys,
      planModeEnabled: planModeEnabled ?? this.planModeEnabled,
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
      healthCheck: healthCheck ?? this.healthCheck,
      logConfig: logConfig ?? this.logConfig,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': webMessagePlatformBuiltinId,
      'name': webMessagePlatformBuiltinName,
      'enabled': enabled,
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
      'allowed_message_types': allowedMessageTypes
          .map((item) => item.storageValue)
          .toList(growable: false),
      'allowed_conversation_modes': allowedConversationModes
          .map((item) => item.storageValue)
          .toList(growable: false),
      'allowed_model_keys': allowedModelKeys,
      'plan_mode_enabled': planModeEnabled,
      'single_message_token_limit': singleMessageTokenLimit,
      'max_messages_per_session': maxMessagesPerSession,
      'session_management_enabled': sessionManagementEnabled,
      'workspace_files_enabled': workspaceFilesEnabled,
      'workspace_file_write_enabled': workspaceFileWriteEnabled,
      'workspace_file_max_bytes': workspaceFileMaxBytes,
      'workspace_file_allowed_extensions': workspaceFileAllowedExtensions,
      'upload_cache_retention_days': uploadCacheRetentionDays,
      'health_check': healthCheck.toJson(),
      'log_config': logConfig.toJson(),
    };
  }
}

int _clampInt(Object? value, int fallback, int min, int max) {
  final raw = value is int
      ? value
      : value is num
      ? value.toInt()
      : int.tryParse('${value ?? ''}'.trim());
  return math.min(max, math.max(min, raw ?? fallback));
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
  if (raw is! List) return List<String>.from(fallback);
  final seen = <String>{};
  final values = <String>[];
  for (final item in raw) {
    final text = '$item'.trim();
    if (text.isEmpty) continue;
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
    final k = '$key'.trim();
    final v = '$value'.trim();
    if (k.isNotEmpty) result[k] = v;
  });
  return result;
}

Set<T> _enumSet<T>(Object? raw, T? Function(String?) parser, Set<T> fallback) {
  if (raw is! List) return Set<T>.from(fallback);
  final result = <T>{};
  for (final item in raw) {
    final parsed = parser('$item');
    if (parsed != null) result.add(parsed);
  }
  return result.isEmpty ? Set<T>.from(fallback) : result;
}
