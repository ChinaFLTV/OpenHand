import 'dart:convert';

import '../../../shared/util/input_value_parsing.dart';

class AiE2bVolumeMount {
  const AiE2bVolumeMount({required this.name, required this.path});

  factory AiE2bVolumeMount.fromJson(Map<String, Object?> json) {
    return AiE2bVolumeMount(
      name: stringFromValue(json['name']).trim(),
      path: stringFromValue(json['path']).trim(),
    );
  }

  final String name;
  final String path;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'path': path,
  };

  @override
  bool operator ==(Object other) {
    return other is AiE2bVolumeMount &&
        other.name == name &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(name, path);
}

class AiE2bSandboxSettings {
  const AiE2bSandboxSettings({
    required this.apiKey,
    required this.domain,
    required this.apiUrl,
    required this.sandboxUrl,
    required this.requestTimeoutMs,
    required this.proxy,
    required this.apiHeaders,
    required this.templateId,
    required this.timeoutSeconds,
    required this.autoPause,
    required this.autoPauseMemory,
    required this.autoResumeEnabled,
    required this.secure,
    required this.allowInternetAccess,
    required this.allowPublicTraffic,
    required this.allowOut,
    required this.denyOut,
    required this.egressProxyAddress,
    required this.egressProxyUsername,
    required this.egressProxyPassword,
    required this.maskRequestHost,
    required this.networkRules,
    required this.metadata,
    required this.environmentVariables,
    required this.mcp,
    required this.iamTokens,
    required this.volumeMounts,
    required this.commandUser,
    required this.commandWorkingDirectory,
  });

  factory AiE2bSandboxSettings.defaults() => defaultValue;

  factory AiE2bSandboxSettings.fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return defaultValue;
    return AiE2bSandboxSettings(
      apiKey: stringFromValue(json['api_key']).trim(),
      domain: nullIfBlank(stringFromValue(json['domain'])) ?? 'e2b.app',
      apiUrl: stringFromValue(json['api_url']).trim(),
      sandboxUrl: stringFromValue(json['sandbox_url']).trim(),
      requestTimeoutMs: _nonNegativeInt(
        json['request_timeout_ms'],
        defaultValue.requestTimeoutMs,
      ),
      proxy: stringFromValue(json['proxy']).trim(),
      apiHeaders: _stringMap(json['api_headers']),
      templateId: nullIfBlank(stringFromValue(json['template_id'])) ?? 'base',
      timeoutSeconds: _nonNegativeInt(
        json['timeout_seconds'],
        defaultValue.timeoutSeconds,
      ),
      autoPause: boolFromValue(json['auto_pause']),
      autoPauseMemory: boolFromValue(
        json['auto_pause_memory'],
        defaultValue: true,
      ),
      autoResumeEnabled: boolFromValue(json['auto_resume_enabled']),
      secure: boolFromValue(json['secure'], defaultValue: true),
      allowInternetAccess: boolFromValue(
        json['allow_internet_access'],
        defaultValue: true,
      ),
      allowPublicTraffic: boolFromValue(
        json['allow_public_traffic'],
        defaultValue: true,
      ),
      allowOut: _stringList(json['allow_out']),
      denyOut: _stringList(json['deny_out']),
      egressProxyAddress: stringFromValue(json['egress_proxy_address']).trim(),
      egressProxyUsername: stringFromValue(
        json['egress_proxy_username'],
      ).trim(),
      egressProxyPassword: stringFromValue(json['egress_proxy_password']),
      maskRequestHost: stringFromValue(json['mask_request_host']).trim(),
      networkRules: _objectMap(json['network_rules']),
      metadata: _stringMap(json['metadata']),
      environmentVariables: _stringMap(json['environment_variables']),
      mcp: _nullableObjectMap(json['mcp']),
      iamTokens: _objectMap(json['iam_tokens']),
      volumeMounts: _volumeMounts(json['volume_mounts']),
      commandUser: stringFromValue(json['command_user']).trim(),
      commandWorkingDirectory:
          nullIfBlank(stringFromValue(json['command_working_directory'])) ??
          '/home/user',
    );
  }

  static const AiE2bSandboxSettings defaultValue = AiE2bSandboxSettings(
    apiKey: '',
    domain: 'e2b.app',
    apiUrl: '',
    sandboxUrl: '',
    requestTimeoutMs: 60000,
    proxy: '',
    apiHeaders: <String, String>{},
    templateId: 'base',
    timeoutSeconds: 300,
    autoPause: false,
    autoPauseMemory: true,
    autoResumeEnabled: false,
    secure: true,
    allowInternetAccess: true,
    allowPublicTraffic: true,
    allowOut: <String>[],
    denyOut: <String>[],
    egressProxyAddress: '',
    egressProxyUsername: '',
    egressProxyPassword: '',
    maskRequestHost: '',
    networkRules: <String, Object?>{},
    metadata: <String, String>{},
    environmentVariables: <String, String>{},
    mcp: null,
    iamTokens: <String, Object?>{},
    volumeMounts: <AiE2bVolumeMount>[],
    commandUser: '',
    commandWorkingDirectory: '/home/user',
  );

  final String apiKey;
  final String domain;
  final String apiUrl;
  final String sandboxUrl;
  final int requestTimeoutMs;
  final String proxy;
  final Map<String, String> apiHeaders;
  final String templateId;
  final int timeoutSeconds;
  final bool autoPause;
  final bool autoPauseMemory;
  final bool autoResumeEnabled;
  final bool secure;
  final bool allowInternetAccess;
  final bool allowPublicTraffic;
  final List<String> allowOut;
  final List<String> denyOut;
  final String egressProxyAddress;
  final String egressProxyUsername;
  final String egressProxyPassword;
  final String maskRequestHost;
  final Map<String, Object?> networkRules;
  final Map<String, String> metadata;
  final Map<String, String> environmentVariables;
  final Map<String, Object?>? mcp;
  final Map<String, Object?> iamTokens;
  final List<AiE2bVolumeMount> volumeMounts;
  final String commandUser;
  final String commandWorkingDirectory;

  Uri get resolvedApiUri {
    final custom = Uri.tryParse(apiUrl.trim());
    return custom != null && custom.hasScheme && custom.host.isNotEmpty
        ? custom
        : Uri.parse('https://api.${domain.trim()}');
  }

  Uri get resolvedSandboxUri {
    final custom = Uri.tryParse(sandboxUrl.trim());
    return custom != null && custom.hasScheme && custom.host.isNotEmpty
        ? custom
        : Uri.parse('https://sandbox.${domain.trim()}');
  }

  bool get isConfigured => apiKey.trim().isNotEmpty && templateId.isNotEmpty;

  AiE2bSandboxSettings copyWith({
    String? apiKey,
    String? domain,
    String? apiUrl,
    String? sandboxUrl,
    int? requestTimeoutMs,
    String? proxy,
    Map<String, String>? apiHeaders,
    String? templateId,
    int? timeoutSeconds,
    bool? autoPause,
    bool? autoPauseMemory,
    bool? autoResumeEnabled,
    bool? secure,
    bool? allowInternetAccess,
    bool? allowPublicTraffic,
    List<String>? allowOut,
    List<String>? denyOut,
    String? egressProxyAddress,
    String? egressProxyUsername,
    String? egressProxyPassword,
    String? maskRequestHost,
    Map<String, Object?>? networkRules,
    Map<String, String>? metadata,
    Map<String, String>? environmentVariables,
    Map<String, Object?>? mcp,
    bool clearMcp = false,
    Map<String, Object?>? iamTokens,
    List<AiE2bVolumeMount>? volumeMounts,
    String? commandUser,
    String? commandWorkingDirectory,
  }) {
    return AiE2bSandboxSettings(
      apiKey: apiKey ?? this.apiKey,
      domain: domain ?? this.domain,
      apiUrl: apiUrl ?? this.apiUrl,
      sandboxUrl: sandboxUrl ?? this.sandboxUrl,
      requestTimeoutMs: requestTimeoutMs ?? this.requestTimeoutMs,
      proxy: proxy ?? this.proxy,
      apiHeaders: apiHeaders ?? this.apiHeaders,
      templateId: templateId ?? this.templateId,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      autoPause: autoPause ?? this.autoPause,
      autoPauseMemory: autoPauseMemory ?? this.autoPauseMemory,
      autoResumeEnabled: autoResumeEnabled ?? this.autoResumeEnabled,
      secure: secure ?? this.secure,
      allowInternetAccess: allowInternetAccess ?? this.allowInternetAccess,
      allowPublicTraffic: allowPublicTraffic ?? this.allowPublicTraffic,
      allowOut: allowOut ?? this.allowOut,
      denyOut: denyOut ?? this.denyOut,
      egressProxyAddress: egressProxyAddress ?? this.egressProxyAddress,
      egressProxyUsername: egressProxyUsername ?? this.egressProxyUsername,
      egressProxyPassword: egressProxyPassword ?? this.egressProxyPassword,
      maskRequestHost: maskRequestHost ?? this.maskRequestHost,
      networkRules: networkRules ?? this.networkRules,
      metadata: metadata ?? this.metadata,
      environmentVariables: environmentVariables ?? this.environmentVariables,
      mcp: clearMcp ? null : (mcp ?? this.mcp),
      iamTokens: iamTokens ?? this.iamTokens,
      volumeMounts: volumeMounts ?? this.volumeMounts,
      commandUser: commandUser ?? this.commandUser,
      commandWorkingDirectory:
          commandWorkingDirectory ?? this.commandWorkingDirectory,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'api_key': apiKey,
    'domain': domain,
    'api_url': apiUrl,
    'sandbox_url': sandboxUrl,
    'request_timeout_ms': requestTimeoutMs,
    'proxy': proxy,
    'api_headers': apiHeaders,
    'template_id': templateId,
    'timeout_seconds': timeoutSeconds,
    'auto_pause': autoPause,
    'auto_pause_memory': autoPauseMemory,
    'auto_resume_enabled': autoResumeEnabled,
    'secure': secure,
    'allow_internet_access': allowInternetAccess,
    'allow_public_traffic': allowPublicTraffic,
    'allow_out': allowOut,
    'deny_out': denyOut,
    'egress_proxy_address': egressProxyAddress,
    'egress_proxy_username': egressProxyUsername,
    'egress_proxy_password': egressProxyPassword,
    'mask_request_host': maskRequestHost,
    'network_rules': networkRules,
    'metadata': metadata,
    'environment_variables': environmentVariables,
    'mcp': mcp,
    'iam_tokens': iamTokens,
    'volume_mounts': volumeMounts.map((item) => item.toJson()).toList(),
    'command_user': commandUser,
    'command_working_directory': commandWorkingDirectory,
  };

  Map<String, Object?> toRuntimeJson() => <String, Object?>{
    'configured': isConfigured,
    'domain': domain,
    'custom_api_url': apiUrl.isNotEmpty,
    'custom_sandbox_url': sandboxUrl.isNotEmpty,
    'request_timeout_ms': requestTimeoutMs,
    'template_id': templateId,
    'timeout_seconds': timeoutSeconds,
    'auto_pause': autoPause,
    'auto_pause_memory': autoPauseMemory,
    'auto_resume_enabled': autoResumeEnabled,
    'secure': secure,
    'allow_internet_access': allowInternetAccess,
    'allow_public_traffic': allowPublicTraffic,
    'allow_out_count': allowOut.length,
    'deny_out_count': denyOut.length,
    'network_rule_count': networkRules.length,
    'metadata_count': metadata.length,
    'environment_variable_count': environmentVariables.length,
    'mcp_configured': mcp != null,
    'iam_token_count': iamTokens.length,
    'volume_mount_count': volumeMounts.length,
    'command_user_configured': commandUser.isNotEmpty,
    'command_working_directory': commandWorkingDirectory,
  };

  @override
  bool operator ==(Object other) {
    return other is AiE2bSandboxSettings &&
        _jsonEquals(other.toJson(), toJson());
  }

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  static int _nonNegativeInt(Object? value, int fallback) {
    final parsed = int.tryParse('$value');
    return parsed == null || parsed < 0 ? fallback : parsed;
  }

  static List<String> _stringList(Object? value) {
    return stringListFromValueOrJsonText(value)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static Map<String, String> _stringMap(Object? value) {
    final source = optionalStringKeyedMapFromValueOrJsonText(value);
    if (source == null) return const <String, String>{};
    return <String, String>{
      for (final entry in source.entries)
        if (entry.key.trim().isNotEmpty)
          entry.key.trim(): stringFromValue(entry.value),
    };
  }

  static Map<String, Object?> _objectMap(Object? value) {
    return optionalStringKeyedMapFromValueOrJsonText(value) ??
        const <String, Object?>{};
  }

  static Map<String, Object?>? _nullableObjectMap(Object? value) {
    if (value == null || value == 'null') return null;
    return optionalStringKeyedMapFromValueOrJsonText(value);
  }

  static List<AiE2bVolumeMount> _volumeMounts(Object? value) {
    final result = <AiE2bVolumeMount>[];
    for (final item in stringKeyedMapListFromValueOrJsonText(value)) {
      final mount = AiE2bVolumeMount.fromJson(item);
      if (mount.name.isNotEmpty && mount.path.isNotEmpty) result.add(mount);
    }
    return result;
  }

  static bool _jsonEquals(Object? left, Object? right) {
    return jsonEncode(left) == jsonEncode(right);
  }
}
