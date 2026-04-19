import 'dart:convert';

import '../../../l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

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
  sglang('sglang'),
  seed('seed'),
  stepfun('stepfun'),
  mimo('mimo'),
  hunyuan('hunyuan');

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
      AiProtocolType.qwen => l10n.aiProtocolQwen,
      AiProtocolType.kimi => l10n.aiProtocolKimi,
      AiProtocolType.glm => l10n.aiProtocolGlm,
      AiProtocolType.grok => l10n.aiProtocolGrok,
      AiProtocolType.ollama => l10n.aiProtocolOllama,
      AiProtocolType.vllm => l10n.aiProtocolVllm,
      AiProtocolType.sglang => l10n.aiProtocolSglang,
      AiProtocolType.seed => l10n.aiProtocolSeed,
      AiProtocolType.stepfun => l10n.aiProtocolStepFun,
      AiProtocolType.mimo => l10n.aiProtocolMimo,
      AiProtocolType.hunyuan => l10n.aiProtocolHunyuan,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-model profile (user-configurable metadata)
// ─────────────────────────────────────────────────────────────────────────────

/// Input/output modalities a model may support.
enum AiModelModality {
  text('text'),
  image('image'),
  video('video'),
  audio('audio');

  const AiModelModality(this.storageValue);
  final String storageValue;

  static AiModelModality? fromStorage(String? value) {
    if (value == null) return null;
    for (final m in values) {
      if (m.storageValue == value) return m;
    }
    return null;
  }
}

/// Creative / generative capabilities a model may expose.
enum AiModelCapability {
  imageGeneration('image_generation'),
  videoGeneration('video_generation'),
  audioGeneration('audio_generation'),
  pdfGeneration('pdf_generation'),
  pptGeneration('ppt_generation');

  const AiModelCapability(this.storageValue);
  final String storageValue;

  static AiModelCapability? fromStorage(String? value) {
    if (value == null) return null;
    for (final c in values) {
      if (c.storageValue == value) return c;
    }
    return null;
  }
}

/// User-configurable per-model metadata that overrides hardcoded heuristics.
///
/// When a field is `null` the system falls back to the default detection logic
/// (pattern matching on model ID, protocol-level flags, etc.).
class AiModelProfile {
  const AiModelProfile({
    this.displayName,
    this.description,
    this.isMultimodal,
    this.supportedModalities = const <AiModelModality>{},
    this.maxContextLength,
    this.maxSummaryLength,
    this.maxOutputLength,
    this.maxThinkingLength,
    this.capabilities = const <AiModelCapability>{},
  });

  factory AiModelProfile.fromJson(Map<String, Object?> json) {
    return AiModelProfile(
      displayName: json['display_name'] as String?,
      description: json['description'] as String?,
      isMultimodal: json['is_multimodal'] as bool?,
      supportedModalities: _parseModalities(json['supported_modalities']),
      maxContextLength: _readNullablePositiveInt(json['max_context_length']),
      maxSummaryLength: _readNullablePositiveInt(json['max_summary_length']),
      maxOutputLength: _readNullablePositiveInt(json['max_output_length']),
      maxThinkingLength: _readNullablePositiveInt(json['max_thinking_length']),
      capabilities: _parseCapabilities(json['capabilities']),
    );
  }

  /// User-friendly display name (e.g. "GPT-4o" instead of "gpt-4o-2024-11-20").
  final String? displayName;

  /// Short model description (free-form text).
  final String? description;

  /// Explicit multimodal toggle. When `null`, inferred from adapter heuristics.
  final bool? isMultimodal;

  /// Which modalities this model can handle. Empty set = use defaults.
  final Set<AiModelModality> supportedModalities;

  /// Token limits. `null` means "use provider/adapter defaults".
  final int? maxContextLength;
  final int? maxSummaryLength;
  final int? maxOutputLength;
  final int? maxThinkingLength;

  /// Creative capabilities this model supports. Empty set = use defaults.
  final Set<AiModelCapability> capabilities;

  /// Whether user explicitly configured this profile (not just empty defaults).
  bool get hasUserOverrides =>
      displayName != null ||
      description != null ||
      isMultimodal != null ||
      supportedModalities.isNotEmpty ||
      maxContextLength != null ||
      maxSummaryLength != null ||
      maxOutputLength != null ||
      maxThinkingLength != null ||
      capabilities.isNotEmpty;

  AiModelProfile copyWith({
    String? displayName,
    bool clearDisplayName = false,
    String? description,
    bool clearDescription = false,
    bool? isMultimodal,
    bool clearIsMultimodal = false,
    Set<AiModelModality>? supportedModalities,
    int? maxContextLength,
    bool clearMaxContextLength = false,
    int? maxSummaryLength,
    bool clearMaxSummaryLength = false,
    int? maxOutputLength,
    bool clearMaxOutputLength = false,
    int? maxThinkingLength,
    bool clearMaxThinkingLength = false,
    Set<AiModelCapability>? capabilities,
  }) {
    return AiModelProfile(
      displayName:
          clearDisplayName ? null : displayName ?? this.displayName,
      description:
          clearDescription ? null : description ?? this.description,
      isMultimodal:
          clearIsMultimodal ? null : isMultimodal ?? this.isMultimodal,
      supportedModalities: supportedModalities ?? this.supportedModalities,
      maxContextLength: clearMaxContextLength
          ? null
          : maxContextLength ?? this.maxContextLength,
      maxSummaryLength: clearMaxSummaryLength
          ? null
          : maxSummaryLength ?? this.maxSummaryLength,
      maxOutputLength: clearMaxOutputLength
          ? null
          : maxOutputLength ?? this.maxOutputLength,
      maxThinkingLength: clearMaxThinkingLength
          ? null
          : maxThinkingLength ?? this.maxThinkingLength,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (displayName != null) 'display_name': displayName,
      if (description != null) 'description': description,
      if (isMultimodal != null) 'is_multimodal': isMultimodal,
      if (supportedModalities.isNotEmpty)
        'supported_modalities': supportedModalities
            .map((m) => m.storageValue)
            .toList(growable: false),
      if (maxContextLength != null) 'max_context_length': maxContextLength,
      if (maxSummaryLength != null) 'max_summary_length': maxSummaryLength,
      if (maxOutputLength != null) 'max_output_length': maxOutputLength,
      if (maxThinkingLength != null) 'max_thinking_length': maxThinkingLength,
      if (capabilities.isNotEmpty)
        'capabilities': capabilities
            .map((c) => c.storageValue)
            .toList(growable: false),
    };
  }

  static Set<AiModelModality> _parseModalities(Object? value) {
    if (value is! List) return const <AiModelModality>{};
    final result = <AiModelModality>{};
    for (final item in value) {
      final m = AiModelModality.fromStorage('$item');
      if (m != null) result.add(m);
    }
    return result;
  }

  static Set<AiModelCapability> _parseCapabilities(Object? value) {
    if (value is! List) return const <AiModelCapability>{};
    final result = <AiModelCapability>{};
    for (final item in value) {
      final c = AiModelCapability.fromStorage('$item');
      if (c != null) result.add(c);
    }
    return result;
  }

  static int? _readNullablePositiveInt(Object? value) {
    if (value is int) return value > 0 ? value : null;
    if (value is num) {
      final n = value.toInt();
      return n > 0 ? n : null;
    }
    final parsed = int.tryParse('${value ?? ''}'.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider configuration
// ─────────────────────────────────────────────────────────────────────────────

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
      modelProfiles: _parseModelProfiles(json['model_profiles']),
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
    this.modelProfiles = const <String, AiModelProfile>{},
  });

  static List<String> normalizeModelIds(Iterable<String> values) {
    final normalized = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        normalized.add(trimmed);
      }
    }
    final sorted = normalized.toList()..sort();
    return sorted.toList(growable: false);
  }

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

  /// Per-model user-configurable profiles, keyed by model ID.
  /// Overrides hardcoded heuristics for vision detection, capabilities, etc.
  final Map<String, AiModelProfile> modelProfiles;

  /// Returns the [AiModelProfile] for the given [id], or an empty default.
  AiModelProfile profileFor(String id) {
    return modelProfiles[id.trim()] ?? const AiModelProfile();
  }

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
    final trimmedModelId = modelId.trim();
    return normalizeModelIds(<String>[
      ...availableModelIds,
      if (trimmedModelId.isNotEmpty) trimmedModelId,
    ]);
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
    Map<String, AiModelProfile>? modelProfiles,
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
      availableModelIds: normalizeModelIds(
        availableModelIds ?? this.availableModelIds,
      ),
      customHeaders: customHeaders ?? this.customHeaders,
      requestMethod: requestMethod ?? this.requestMethod,
      maxTokens: clearMaxTokens ? null : maxTokens ?? this.maxTokens,
      temperature: clearTemperature ? null : temperature ?? this.temperature,
      streamEnabled: streamEnabled ?? this.streamEnabled,
      modelProfiles: modelProfiles ?? this.modelProfiles,
    );
  }

  Map<String, Object?> toJson() {
    final profilesJson = <String, Object?>{};
    for (final entry in modelProfiles.entries) {
      if (entry.value.hasUserOverrides) {
        profilesJson[entry.key] = entry.value.toJson();
      }
    }
    return <String, Object?>{
      'id': id,
      'name': name,
      'base_url': normalizedBaseUrl,
      'auth_scheme': authScheme.storageValue,
      'token': token,
      'model_id': modelId.trim(),
      'protocol_type': protocolType.storageValue,
      'max_context_tokens': maxContextTokens,
      'available_model_ids': normalizeModelIds(availableModelIds),
      'custom_headers': customHeaders,
      'request_method': requestMethod,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'stream_enabled': streamEnabled,
      if (profilesJson.isNotEmpty) 'model_profiles': profilesJson,
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
      return normalizeModelIds(<String>[
        for (final item in value)
          if ('$item'.trim().isNotEmpty) '$item'.trim(),
      ]);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return const <String>[];
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return normalizeModelIds(<String>[
            for (final item in decoded)
              if ('$item'.trim().isNotEmpty) '$item'.trim(),
          ]);
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

  static Map<String, AiModelProfile> _parseModelProfiles(Object? value) {
    if (value == null) return const <String, AiModelProfile>{};
    Map<String, dynamic>? map;
    if (value is Map) {
      map = value.cast<String, dynamic>();
    } else if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return const <String, AiModelProfile>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          map = decoded.cast<String, dynamic>();
        }
      } catch (_) {
        // Not valid JSON — ignore.
      }
    }
    if (map == null) return const <String, AiModelProfile>{};
    final result = <String, AiModelProfile>{};
    for (final entry in map.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      if (entry.value is Map) {
        result[key] = AiModelProfile.fromJson(
          (entry.value as Map).cast<String, Object?>(),
        );
      }
    }
    return result;
  }
}
