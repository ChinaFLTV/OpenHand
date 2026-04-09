import 'dart:convert';

import '../../../l10n/app_localizations.dart';

enum AiAuthScheme {
  none('none'),
  bearer('bearer'),
  token('token'),
  apiKey('api_key');

  const AiAuthScheme(this.storageValue);

  final String storageValue;

  static bool isValidStorageValue(String? value) {
    return AiAuthScheme.values.any((item) => item.storageValue == value);
  }

  static AiAuthScheme fromStorage(String? value) {
    return AiAuthScheme.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AiAuthScheme.bearer,
    );
  }

  String label(AppLocalizations l10n) {
    return switch (this) {
      AiAuthScheme.none => l10n.aiAuthNone,
      AiAuthScheme.bearer => l10n.aiAuthBearer,
      AiAuthScheme.token => l10n.aiAuthToken,
      AiAuthScheme.apiKey => l10n.aiAuthApiKey,
    };
  }

  String apply(String rawToken) {
    return switch (this) {
      AiAuthScheme.none => '',
      AiAuthScheme.bearer => 'Bearer $rawToken',
      AiAuthScheme.token => 'Token $rawToken',
      AiAuthScheme.apiKey => rawToken,
    };
  }
}

enum AiProtocolType {
  openai('openai'),
  claude('claude'),
  gemini('gemini'),
  deepseek('deepseek'),
  qwen('qwen'),
  kimi('kimi'),
  glm('glm'),
  grok('grok'),
  ollama('ollama'),
  vllm('vllm'),
  sglang('sglang');

  const AiProtocolType(this.storageValue);

  final String storageValue;

  static bool isValidStorageValue(String? value) {
    return AiProtocolType.values.any((item) => item.storageValue == value);
  }

  static AiProtocolType fromStorage(String? value) {
    return AiProtocolType.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AiProtocolType.openai,
    );
  }

  String label(AppLocalizations l10n) {
    return switch (this) {
      AiProtocolType.openai => l10n.aiProtocolOpenAi,
      AiProtocolType.claude => l10n.aiProtocolClaude,
      AiProtocolType.gemini => l10n.aiProtocolGemini,
      AiProtocolType.deepseek => l10n.aiProtocolDeepSeek,
      AiProtocolType.qwen => 'Qwen',
      AiProtocolType.kimi => l10n.aiProtocolKimi,
      AiProtocolType.glm => l10n.aiProtocolGlm,
      AiProtocolType.grok => l10n.aiProtocolGrok,
      AiProtocolType.ollama => l10n.aiProtocolOllama,
      AiProtocolType.vllm => l10n.aiProtocolVllm,
      AiProtocolType.sglang => l10n.aiProtocolSglang,
    };
  }
}

class AiModelConfig {

  factory AiModelConfig.fromJson(Map<String, Object?> json) {
    final availableModelIds = _parseAvailableModelIds(
      json['available_model_ids'],
    );
    return AiModelConfig(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      baseUrl: _normalizeBaseUrl('${json['base_url'] ?? ''}'),
      authScheme: AiAuthScheme.fromStorage('${json['auth_scheme'] ?? ''}'),
      token: '${json['token'] ?? ''}',
      modelId: '${json['model_id'] ?? ''}'.trim(),
      protocolType: AiProtocolType.fromStorage(
        '${json['protocol_type'] ?? ''}',
      ),
      maxContextTokens: _readNullablePositiveInt(json['max_context_tokens']),
      availableModelIds: availableModelIds,
      customHeaders: _parseCustomHeaders(json['custom_headers']),
      requestMethod: _parseRequestMethod(json['request_method']),
      maxTokens: _readNullablePositiveInt(json['max_tokens']),
      temperature: _readNullableDouble(json['temperature']),
      streamEnabled: json['stream_enabled'] as bool? ?? true,
    );
  }
  const AiModelConfig({
    required this.id,
    this.name = '',
    required this.baseUrl,
    required this.authScheme,
    required this.token,
    required this.modelId,
    required this.protocolType,
    this.maxContextTokens,
    this.availableModelIds = const <String>[],
    this.customHeaders = const <String, String>{},
    this.requestMethod = 'POST',
    this.maxTokens,
    this.temperature,
    this.streamEnabled = true,
  });

  final String id;

  /// User-defined display name for this provider (e.g. "DeepSeek", "本地 Ollama").
  /// When empty, [providerLabel] falls back to extracting the host from [baseUrl].
  final String name;

  final String baseUrl;
  final AiAuthScheme authScheme;
  final String token;

  /// The currently active model ID for this provider.
  final String modelId;
  final AiProtocolType protocolType;
  final int? maxContextTokens;

  /// All known model IDs for this provider (auto-scanned + manually added).
  final List<String> availableModelIds;

  /// User-defined custom HTTP headers to include in API requests.
  final Map<String, String> customHeaders;

  /// HTTP request method (default: POST).
  final String requestMethod;

  /// Maximum tokens for the response. When null, uses the adapter default.
  final int? maxTokens;

  /// Temperature for response generation. When null, uses the adapter default (0.7).
  final double? temperature;

  /// Whether to use server-sent events (SSE) streaming for responses.
  final bool streamEnabled;

  String get normalizedBaseUrl => _normalizeBaseUrl(baseUrl);

  /// Short display label for the provider.
  /// Prefers the user-defined [name]; falls back to the base URL host;
  /// falls back to the protocol type.
  String get providerLabel {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) return trimmedName;
    final host = Uri.tryParse(normalizedBaseUrl)?.host ?? normalizedBaseUrl;
    if (host.isEmpty) {
      return protocolType.storageValue.toUpperCase();
    }
    return host;
  }

  String get displayName {
    final trimmedModelId = modelId.trim();
    if (trimmedModelId.isNotEmpty) {
      return trimmedModelId;
    }
    return protocolType.storageValue.toUpperCase();
  }

  String get maskedToken {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      return '';
    }
    if (trimmedToken.length <= 8) {
      return '*' * trimmedToken.length;
    }
    final visibleSuffix = trimmedToken.substring(trimmedToken.length - 4);
    return '${'*' * (trimmedToken.length - 4)}$visibleSuffix';
  }

  /// Returns a deduplicated, sorted list merging [availableModelIds] and
  /// the current [modelId] (if non-empty).
  List<String> get allModelIds {
    final ids = <String>{...availableModelIds};
    final trimmedModelId = modelId.trim();
    if (trimmedModelId.isNotEmpty) {
      ids.add(trimmedModelId);
    }
    final sorted = ids.toList()..sort();
    return sorted;
  }

  AiModelConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    AiAuthScheme? authScheme,
    String? token,
    String? modelId,
    AiProtocolType? protocolType,
    int? maxContextTokens,
    bool clearMaxContextTokens = false,
    List<String>? availableModelIds,
    Map<String, String>? customHeaders,
    String? requestMethod,
    int? maxTokens,
    bool clearMaxTokens = false,
    double? temperature,
    bool clearTemperature = false,
    bool? streamEnabled,
  }) {
    return AiModelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: _normalizeBaseUrl(baseUrl ?? this.baseUrl),
      authScheme: authScheme ?? this.authScheme,
      token: token ?? this.token,
      modelId: modelId ?? this.modelId,
      protocolType: protocolType ?? this.protocolType,
      maxContextTokens: clearMaxContextTokens
          ? null
          : maxContextTokens ?? this.maxContextTokens,
      availableModelIds: availableModelIds ?? this.availableModelIds,
      customHeaders: customHeaders ?? this.customHeaders,
      requestMethod: requestMethod ?? this.requestMethod,
      maxTokens: clearMaxTokens ? null : maxTokens ?? this.maxTokens,
      temperature: clearTemperature ? null : temperature ?? this.temperature,
      streamEnabled: streamEnabled ?? this.streamEnabled,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'base_url': normalizedBaseUrl,
      'auth_scheme': authScheme.storageValue,
      'token': token,
      'model_id': modelId.trim(),
      'protocol_type': protocolType.storageValue,
      'max_context_tokens': maxContextTokens,
      'available_model_ids': availableModelIds,
      'custom_headers': customHeaders,
      'request_method': requestMethod,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'stream_enabled': streamEnabled,
    };
  }

  static String _normalizeBaseUrl(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return '';
    }
    return trimmedValue.endsWith('/')
        ? trimmedValue.substring(0, trimmedValue.length - 1)
        : trimmedValue;
  }

  static int? _readNullablePositiveInt(Object? value) {
    if (value is int) {
      return value > 0 ? value : null;
    }
    if (value is num) {
      final normalized = value.toInt();
      return normalized > 0 ? normalized : null;
    }
    final parsed = int.tryParse('${value ?? ''}'.trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  /// Parses `available_model_ids` which may be:
  /// - a `List<dynamic>` (from JSON deserialization)
  /// - a `String` (double-JSON-encoded from TOML storage)
  /// - null or other (returns empty list)
  static List<String> _parseAvailableModelIds(Object? value) {
    if (value == null) {
      return const <String>[];
    }
    if (value is List) {
      return <String>[
        for (final item in value)
          if ('$item'.trim().isNotEmpty) '$item'.trim(),
      ];
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return const <String>[];
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return <String>[
            for (final item in decoded)
              if ('$item'.trim().isNotEmpty) '$item'.trim(),
          ];
        }
      } catch (_) {
        // Not valid JSON — ignore.
      }
    }
    return const <String>[];
  }

  static Map<String, String> _parseCustomHeaders(Object? value) {
    if (value == null) {
      return const <String, String>{};
    }
    if (value is Map) {
      final result = <String, String>{};
      for (final entry in value.entries) {
        final key = '${entry.key}'.trim();
        final val = '${entry.value}'.trim();
        if (key.isNotEmpty) {
          result[key] = val;
        }
      }
      return result;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return const <String, String>{};
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return _parseCustomHeaders(decoded);
        }
      } catch (_) {
        // Not valid JSON — ignore.
      }
    }
    return const <String, String>{};
  }

  static double? _readNullableDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    final parsed = double.tryParse('${value ?? ''}'.trim());
    return parsed;
  }

  static String _parseRequestMethod(Object? value) {
    final raw = '${value ?? ''}'.trim().toUpperCase();
    if (raw.isEmpty) return 'POST';
    return raw;
  }
}
