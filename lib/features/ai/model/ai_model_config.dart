import 'dart:convert';

import '../../../l10n/app_localizations.dart';
import 'ai_api_dialect.dart';
import 'ai_api_family.dart';
import 'ai_endpoint_override.dart';
import 'ai_model_catalog.dart';
import 'ai_operation_routing.dart';
import 'ai_realtime_config.dart';

List<String> _parseStringListLoose(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

class AiModelArchitectureMetadata {
  const AiModelArchitectureMetadata({
    this.modality,
    this.inputModalities = const <String>[],
    this.outputModalities = const <String>[],
    this.tokenizer,
    this.instructType,
  });

  factory AiModelArchitectureMetadata.fromJson(Map<String, Object?> json) {
    return AiModelArchitectureMetadata(
      modality: json['modality'] as String?,
      inputModalities: _parseStringListLoose(json['input_modalities']),
      outputModalities: _parseStringListLoose(json['output_modalities']),
      tokenizer: json['tokenizer'] as String?,
      instructType: json['instruct_type'] as String?,
    );
  }

  final String? modality;
  final List<String> inputModalities;
  final List<String> outputModalities;
  final String? tokenizer;
  final String? instructType;

  bool get isEmpty =>
      modality == null &&
      inputModalities.isEmpty &&
      outputModalities.isEmpty &&
      tokenizer == null &&
      instructType == null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (modality != null) 'modality': modality,
      if (inputModalities.isNotEmpty) 'input_modalities': inputModalities,
      if (outputModalities.isNotEmpty) 'output_modalities': outputModalities,
      if (tokenizer != null) 'tokenizer': tokenizer,
      if (instructType != null) 'instruct_type': instructType,
    };
  }
}

class AiModelLinksMetadata {
  const AiModelLinksMetadata({this.details});

  factory AiModelLinksMetadata.fromJson(Map<String, Object?> json) {
    return AiModelLinksMetadata(details: json['details'] as String?);
  }

  final String? details;

  bool get isEmpty => details == null || details!.trim().isEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{if (details != null) 'details': details};
  }
}

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
  minimax('minimax'),
  longcat('longcat'),
  joycode('joycode'),
  wenxin('wenxin'),
  meta('meta'),
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
      AiProtocolType.minimax => l10n.aiProtocolMinimax,
      AiProtocolType.longcat => l10n.aiProtocolLongCat,
      AiProtocolType.joycode => l10n.aiProtocolJoyCode,
      AiProtocolType.wenxin => l10n.aiProtocolWenxin,
      AiProtocolType.meta => l10n.aiProtocolMeta,
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
  audio('audio'),
  file('file');

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
    this.requiresReasoningEcho,
    this.capabilities = const <AiModelCapability>{},
    this.supportsAttachments,
    this.inputUsdPer1M,
    this.outputUsdPer1M,
    this.cacheReadUsdPer1M,
    this.cacheWriteUsdPer1M,
    this.canonicalSlug,
    this.huggingFaceId,
    this.created,
    this.architecture,
    this.supportedParameters = const <String>[],
    this.defaultParameters = const <String, Object?>{},
    this.supportedVoices = const <String>[],
    this.knowledgeCutoff,
    this.expirationDate,
    this.links,
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
      requiresReasoningEcho: json['requires_reasoning_echo'] as bool?,
      capabilities: _parseCapabilities(json['capabilities']),
      supportsAttachments: json['supports_attachments'] as bool?,
      inputUsdPer1M: _readNullableNonNegativeDouble(json['input_usd_per_1m']),
      outputUsdPer1M: _readNullableNonNegativeDouble(json['output_usd_per_1m']),
      cacheReadUsdPer1M: _readNullableNonNegativeDouble(
        json['cache_read_usd_per_1m'],
      ),
      cacheWriteUsdPer1M: _readNullableNonNegativeDouble(
        json['cache_write_usd_per_1m'],
      ),
      canonicalSlug: json['canonical_slug'] as String?,
      huggingFaceId: json['hugging_face_id'] as String?,
      created: _readNullableInt(json['created']),
      architecture: json['architecture'] is Map<String, Object?>
          ? AiModelArchitectureMetadata.fromJson(
              json['architecture'] as Map<String, Object?>,
            )
          : json['architecture'] is Map
          ? AiModelArchitectureMetadata.fromJson(
              Map<String, Object?>.from(json['architecture'] as Map),
            )
          : null,
      supportedParameters: _parseStringList(json['supported_parameters']),
      defaultParameters: _parseObjectMap(json['default_parameters']),
      supportedVoices: _parseStringList(json['supported_voices']),
      knowledgeCutoff: json['knowledge_cutoff'] as String?,
      expirationDate: json['expiration_date'] as String?,
      links: json['links'] is Map<String, Object?>
          ? AiModelLinksMetadata.fromJson(json['links'] as Map<String, Object?>)
          : json['links'] is Map
          ? AiModelLinksMetadata.fromJson(
              Map<String, Object?>.from(json['links'] as Map),
            )
          : null,
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

  /// Whether follow-up requests must echo prior reasoning_content. When null,
  /// the runtime falls back to provider/model-name heuristics.
  final bool? requiresReasoningEcho;

  /// Creative capabilities this model supports. Empty set = use defaults.
  final Set<AiModelCapability> capabilities;

  /// Explicit “supports attachments” toggle. `null` = inherit from catalog
  /// / heuristics (image-modality or multimodal flag enables attachments).
  /// `true` / `false` = user override.
  final bool? supportsAttachments;

  /// 2026-05-04 — 成本控制：每百万 token 的价格（单位 USD）。
  /// `null` = 未配置，成本推算将被跳过。由用户手动填入厄商官方
  /// pricing 页的数据，应避免 LLM 凭空估算。
  final double? inputUsdPer1M;
  final double? outputUsdPer1M;

  /// 缓存命中读取价（一般为输入价的 0.1–0.25）。
  final double? cacheReadUsdPer1M;

  /// 缓存创建写入价（一般为输入价的 1.25）。
  final double? cacheWriteUsdPer1M;

  /// OpenRouter raw fields mirrored 1:1 where available.
  final String? canonicalSlug;
  final String? huggingFaceId;
  final int? created;
  final AiModelArchitectureMetadata? architecture;
  final List<String> supportedParameters;
  final Map<String, Object?> defaultParameters;
  final List<String> supportedVoices;
  final String? knowledgeCutoff;
  final String? expirationDate;
  final AiModelLinksMetadata? links;

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
      requiresReasoningEcho != null ||
      capabilities.isNotEmpty ||
      supportsAttachments != null ||
      inputUsdPer1M != null ||
      outputUsdPer1M != null ||
      cacheReadUsdPer1M != null ||
      cacheWriteUsdPer1M != null ||
      canonicalSlug != null ||
      huggingFaceId != null ||
      created != null ||
      architecture != null ||
      supportedParameters.isNotEmpty ||
      defaultParameters.isNotEmpty ||
      supportedVoices.isNotEmpty ||
      knowledgeCutoff != null ||
      expirationDate != null ||
      links != null;

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
    bool? requiresReasoningEcho,
    bool clearRequiresReasoningEcho = false,
    Set<AiModelCapability>? capabilities,
    bool? supportsAttachments,
    bool clearSupportsAttachments = false,
    double? inputUsdPer1M,
    bool clearInputUsdPer1M = false,
    double? outputUsdPer1M,
    bool clearOutputUsdPer1M = false,
    double? cacheReadUsdPer1M,
    bool clearCacheReadUsdPer1M = false,
    double? cacheWriteUsdPer1M,
    bool clearCacheWriteUsdPer1M = false,
    String? canonicalSlug,
    bool clearCanonicalSlug = false,
    String? huggingFaceId,
    bool clearHuggingFaceId = false,
    int? created,
    bool clearCreated = false,
    AiModelArchitectureMetadata? architecture,
    bool clearArchitecture = false,
    List<String>? supportedParameters,
    Map<String, Object?>? defaultParameters,
    List<String>? supportedVoices,
    String? knowledgeCutoff,
    bool clearKnowledgeCutoff = false,
    String? expirationDate,
    bool clearExpirationDate = false,
    AiModelLinksMetadata? links,
    bool clearLinks = false,
  }) {
    return AiModelProfile(
      displayName: clearDisplayName ? null : displayName ?? this.displayName,
      description: clearDescription ? null : description ?? this.description,
      isMultimodal: clearIsMultimodal
          ? null
          : isMultimodal ?? this.isMultimodal,
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
      requiresReasoningEcho: clearRequiresReasoningEcho
          ? null
          : requiresReasoningEcho ?? this.requiresReasoningEcho,
      capabilities: capabilities ?? this.capabilities,
      supportsAttachments: clearSupportsAttachments
          ? null
          : supportsAttachments ?? this.supportsAttachments,
      inputUsdPer1M: clearInputUsdPer1M
          ? null
          : inputUsdPer1M ?? this.inputUsdPer1M,
      outputUsdPer1M: clearOutputUsdPer1M
          ? null
          : outputUsdPer1M ?? this.outputUsdPer1M,
      cacheReadUsdPer1M: clearCacheReadUsdPer1M
          ? null
          : cacheReadUsdPer1M ?? this.cacheReadUsdPer1M,
      cacheWriteUsdPer1M: clearCacheWriteUsdPer1M
          ? null
          : cacheWriteUsdPer1M ?? this.cacheWriteUsdPer1M,
      canonicalSlug: clearCanonicalSlug
          ? null
          : canonicalSlug ?? this.canonicalSlug,
      huggingFaceId: clearHuggingFaceId
          ? null
          : huggingFaceId ?? this.huggingFaceId,
      created: clearCreated ? null : created ?? this.created,
      architecture: clearArchitecture
          ? null
          : architecture ?? this.architecture,
      supportedParameters: supportedParameters ?? this.supportedParameters,
      defaultParameters: defaultParameters ?? this.defaultParameters,
      supportedVoices: supportedVoices ?? this.supportedVoices,
      knowledgeCutoff: clearKnowledgeCutoff
          ? null
          : knowledgeCutoff ?? this.knowledgeCutoff,
      expirationDate: clearExpirationDate
          ? null
          : expirationDate ?? this.expirationDate,
      links: clearLinks ? null : links ?? this.links,
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
      if (requiresReasoningEcho != null)
        'requires_reasoning_echo': requiresReasoningEcho,
      if (capabilities.isNotEmpty)
        'capabilities': capabilities
            .map((c) => c.storageValue)
            .toList(growable: false),
      if (supportsAttachments != null)
        'supports_attachments': supportsAttachments,
      if (inputUsdPer1M != null) 'input_usd_per_1m': inputUsdPer1M,
      if (outputUsdPer1M != null) 'output_usd_per_1m': outputUsdPer1M,
      if (cacheReadUsdPer1M != null) 'cache_read_usd_per_1m': cacheReadUsdPer1M,
      if (cacheWriteUsdPer1M != null)
        'cache_write_usd_per_1m': cacheWriteUsdPer1M,
      if (canonicalSlug != null) 'canonical_slug': canonicalSlug,
      if (huggingFaceId != null) 'hugging_face_id': huggingFaceId,
      if (created != null) 'created': created,
      if (architecture != null && !architecture!.isEmpty)
        'architecture': architecture!.toJson(),
      if (supportedParameters.isNotEmpty)
        'supported_parameters': supportedParameters,
      if (defaultParameters.isNotEmpty) 'default_parameters': defaultParameters,
      if (supportedVoices.isNotEmpty) 'supported_voices': supportedVoices,
      if (knowledgeCutoff != null) 'knowledge_cutoff': knowledgeCutoff,
      if (expirationDate != null) 'expiration_date': expirationDate,
      if (links != null && !links!.isEmpty) 'links': links!.toJson(),
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

  static List<String> _parseStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, Object?> _parseObjectMap(Object? value) {
    if (value is Map<String, Object?>) {
      return Map<String, Object?>.from(value);
    }
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    return const <String, Object?>{};
  }

  static int? _readNullableInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse('${value ?? ''}'.trim());
    return parsed;
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

  static double? _readNullableNonNegativeDouble(Object? value) {
    double? d;
    if (value is double) {
      d = value;
    } else if (value is num) {
      d = value.toDouble();
    } else if (value is String) {
      d = double.tryParse(value.trim());
    }
    if (d == null || !d.isFinite || d.isNaN || d < 0) return null;
    return d;
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
    final protocolType = AiProtocolType.fromStorage(
      '${json['protocol_type'] ?? ''}',
    );
    final rawApiDialect = '${json['api_dialect'] ?? ''}'.trim();
    final rawProviderKind = '${json['provider_kind'] ?? ''}'.trim();
    return AiModelConfig(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      baseUrl: _normalizeBaseUrl('${json['base_url'] ?? ''}'),
      authScheme: AiAuthScheme.fromStorage('${json['auth_scheme'] ?? ''}'),
      token: '${json['token'] ?? ''}',
      modelId: '${json['model_id'] ?? ''}'.trim(),
      protocolType: protocolType,
      apiDialect: rawApiDialect.isEmpty
          ? inferAiApiDialect(protocolType)
          : AiApiDialect.fromStorage(rawApiDialect),
      providerKind: rawProviderKind.isEmpty
          ? inferAiProviderKind(protocolType)
          : AiProviderKind.fromStorage(rawProviderKind),
      maxContextTokens: _readNullablePositiveInt(json['max_context_tokens']),
      availableModelIds: availableModelIds,
      customHeaders: _parseCustomHeaders(json['custom_headers']),
      requestMethod: _parseRequestMethod(json['request_method']),
      maxTokens: _readNullablePositiveInt(json['max_tokens']),
      temperature: _readNullableDouble(json['temperature']),
      streamEnabled: json['stream_enabled'] as bool? ?? true,
      modelProfiles: _parseModelProfiles(json['model_profiles']),
      endpointOverrides: parseAiEndpointOverrides(json['endpoint_overrides']),
      operationRouting:
          AiOperationRouting.fromJson(json['operation_routing']) ??
          const AiOperationRouting(),
      capabilityOverrides: _parseCapabilityOverrides(
        json['capability_overrides'],
      ),
      operationExtras: _parseOperationExtras(json['operation_extras']),
      realtime:
          AiRealtimeConfig.fromJson(json['realtime']) ??
          const AiRealtimeConfig(),
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
    this.apiDialect = AiApiDialect.openAiCompat,
    this.providerKind = AiProviderKind.custom,
    this.maxContextTokens,
    this.availableModelIds = const <String>[],
    this.customHeaders = const <String, String>{},
    this.requestMethod = 'POST',
    this.maxTokens,
    this.temperature,
    this.streamEnabled = true,
    this.modelProfiles = const <String, AiModelProfile>{},
    this.endpointOverrides = const <AiApiFamily, AiEndpointOverride>{},
    this.operationRouting = const AiOperationRouting(),
    this.capabilityOverrides = const <AiApiFamily, String>{},
    this.operationExtras = const <String, Object?>{},
    this.realtime = const AiRealtimeConfig(),
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
  final AiApiDialect apiDialect;
  final AiProviderKind providerKind;
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

  final Map<AiApiFamily, AiEndpointOverride> endpointOverrides;
  final AiOperationRouting operationRouting;
  final Map<AiApiFamily, String> capabilityOverrides;
  final Map<String, Object?> operationExtras;
  final AiRealtimeConfig realtime;

  /// Returns the effective [AiModelProfile] for the given [id].
  ///
  /// Resolution order:
  /// 1. User-saved per-model overrides from [modelProfiles]
  /// 2. Built-in catalog defaults from [AiModelCatalog]
  /// 3. Empty profile when neither exists
  ///
  /// When both (1) and (2) exist, the user profile wins field-by-field while
  /// leaving catalog defaults in place for any fields the user did not set.
  AiModelProfile profileFor(String id) {
    final trimmedId = id.trim();
    final override = modelProfiles[trimmedId];
    final catalog = AiModelCatalog.lookup(trimmedId, protocolType);
    if (override == null) {
      return catalog ?? const AiModelProfile();
    }
    if (catalog == null) {
      return override;
    }
    return catalog.copyWith(
      displayName: override.displayName,
      description: override.description,
      isMultimodal: override.isMultimodal,
      supportedModalities: override.supportedModalities.isNotEmpty
          ? override.supportedModalities
          : catalog.supportedModalities,
      maxContextLength: override.maxContextLength,
      maxSummaryLength: override.maxSummaryLength,
      maxOutputLength: override.maxOutputLength,
      maxThinkingLength: override.maxThinkingLength,
      requiresReasoningEcho: override.requiresReasoningEcho,
      capabilities: override.capabilities.isNotEmpty
          ? override.capabilities
          : catalog.capabilities,
      supportsAttachments: override.supportsAttachments,
      inputUsdPer1M: override.inputUsdPer1M,
      outputUsdPer1M: override.outputUsdPer1M,
      cacheReadUsdPer1M: override.cacheReadUsdPer1M,
      cacheWriteUsdPer1M: override.cacheWriteUsdPer1M,
      canonicalSlug: override.canonicalSlug,
      huggingFaceId: override.huggingFaceId,
      created: override.created,
      architecture: override.architecture,
      supportedParameters: override.supportedParameters.isNotEmpty
          ? override.supportedParameters
          : catalog.supportedParameters,
      defaultParameters: override.defaultParameters.isNotEmpty
          ? override.defaultParameters
          : catalog.defaultParameters,
      supportedVoices: override.supportedVoices.isNotEmpty
          ? override.supportedVoices
          : catalog.supportedVoices,
      knowledgeCutoff: override.knowledgeCutoff,
      expirationDate: override.expirationDate,
      links: override.links,
    );
  }

  /// Resolves whether the *current* model accepts user-uploaded attachments.
  ///
  /// Resolution order:
  /// 1. Explicit user override on the per-model profile (`supportsAttachments`).
  /// 2. Heuristic: `isMultimodal == true` or the resolved supported modalities
  ///    include [AiModelModality.image] / [AiModelModality.file].
  /// 3. Default `true` — most providers can accept text-style attachments
  ///    (PDF, code, spreadsheets) inlined into the prompt regardless of
  ///    vision capability; image attachments will simply be rejected by the
  ///    adapter when the model truly can't ingest them.
  bool get resolvedSupportsAttachments {
    final profile = profileFor(modelId);
    final explicit = profile.supportsAttachments;
    if (explicit != null) return explicit;
    if (profile.isMultimodal == true) return true;
    if (profile.supportedModalities.contains(AiModelModality.image) ||
        profile.supportedModalities.contains(AiModelModality.file)) {
      return true;
    }
    return true;
  }

  bool get requiresReasoningEcho {
    final profile = profileFor(modelId);
    final explicit = profile.requiresReasoningEcho;
    if (explicit != null) {
      return explicit;
    }
    final normalizedModelId = modelId.trim().toLowerCase();
    if (normalizedModelId.isEmpty) {
      return false;
    }
    return normalizedModelId.startsWith('deepseek-reasoner') ||
        normalizedModelId.startsWith('deepseek-r1') ||
        normalizedModelId.startsWith('deepseek-v4-pro') ||
        normalizedModelId == 'deepseek-v4';
  }

  String get normalizedBaseUrl => _normalizeBaseUrl(baseUrl);

  String resolveOperationModelId(AiApiFamily family) {
    return operationRouting.resolveModelId(family, modelId) ?? modelId.trim();
  }

  String? capabilityStatusFor(AiApiFamily family) {
    final status = capabilityOverrides[family]?.trim();
    return status == null || status.isEmpty ? null : status;
  }

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
    AiApiDialect? apiDialect,
    AiProviderKind? providerKind,
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
    Map<AiApiFamily, AiEndpointOverride>? endpointOverrides,
    AiOperationRouting? operationRouting,
    Map<AiApiFamily, String>? capabilityOverrides,
    Map<String, Object?>? operationExtras,
    AiRealtimeConfig? realtime,
  }) {
    return AiModelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: _normalizeBaseUrl(baseUrl ?? this.baseUrl),
      authScheme: authScheme ?? this.authScheme,
      token: token ?? this.token,
      modelId: modelId ?? this.modelId,
      protocolType: protocolType ?? this.protocolType,
      apiDialect: apiDialect ?? this.apiDialect,
      providerKind: providerKind ?? this.providerKind,
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
      endpointOverrides: endpointOverrides ?? this.endpointOverrides,
      operationRouting: operationRouting ?? this.operationRouting,
      capabilityOverrides: capabilityOverrides ?? this.capabilityOverrides,
      operationExtras: operationExtras ?? this.operationExtras,
      realtime: realtime ?? this.realtime,
    );
  }

  Map<String, Object?> toJson() {
    final profilesJson = <String, Object?>{};
    for (final entry in modelProfiles.entries) {
      if (entry.value.hasUserOverrides) {
        profilesJson[entry.key] = entry.value.toJson();
      }
    }
    final endpointOverridesJson = aiEndpointOverridesToJson(endpointOverrides);
    final capabilityOverridesJson = <String, Object?>{};
    for (final entry in capabilityOverrides.entries) {
      final value = entry.value.trim();
      if (value.isNotEmpty) {
        capabilityOverridesJson[entry.key.storageValue] = value;
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
      'api_dialect': apiDialect.storageValue,
      'provider_kind': providerKind.storageValue,
      'max_context_tokens': maxContextTokens,
      'available_model_ids': normalizeModelIds(availableModelIds),
      'custom_headers': customHeaders,
      'request_method': requestMethod,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'stream_enabled': streamEnabled,
      if (profilesJson.isNotEmpty) 'model_profiles': profilesJson,
      if (endpointOverridesJson.isNotEmpty)
        'endpoint_overrides': endpointOverridesJson,
      if (!operationRouting.isEmpty) 'operation_routing': operationRouting.toJson(),
      if (capabilityOverridesJson.isNotEmpty)
        'capability_overrides': capabilityOverridesJson,
      if (operationExtras.isNotEmpty) 'operation_extras': operationExtras,
      if (!realtime.isEmpty) 'realtime': realtime.toJson(),
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

  static Map<AiApiFamily, String> _parseCapabilityOverrides(Object? value) {
    if (value is! Map) return const <AiApiFamily, String>{};
    final result = <AiApiFamily, String>{};
    for (final entry in value.entries) {
      final family = AiApiFamily.fromStorage('${entry.key}'.trim());
      final status = '${entry.value ?? ''}'.trim();
      if (family == null || status.isEmpty) continue;
      result[family] = status;
    }
    return result;
  }

  static Map<String, Object?> _parseOperationExtras(Object? value) {
    if (value is Map<String, Object?>) {
      return Map<String, Object?>.from(value);
    }
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return const <String, Object?>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, Object?>) {
          return Map<String, Object?>.from(decoded);
        }
        if (decoded is Map) {
          return Map<String, Object?>.from(decoded);
        }
      } catch (_) {
        // Not valid JSON — ignore.
      }
    }
    return const <String, Object?>{};
  }
}

AiApiDialect inferAiApiDialect(AiProtocolType protocolType) {
  return switch (protocolType) {
    AiProtocolType.claude => AiApiDialect.anthropicNative,
    AiProtocolType.gemini => AiApiDialect.geminiNative,
    _ => AiApiDialect.openAiCompat,
  };
}

AiProviderKind inferAiProviderKind(AiProtocolType protocolType) {
  return switch (protocolType) {
    AiProtocolType.openai => AiProviderKind.openai,
    AiProtocolType.claude => AiProviderKind.claude,
    AiProtocolType.gemini => AiProviderKind.gemini,
    AiProtocolType.qwen => AiProviderKind.qwen,
    AiProtocolType.minimax => AiProviderKind.minimax,
    _ => AiProviderKind.custom,
  };
}
