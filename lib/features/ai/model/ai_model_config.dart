import 'dart:convert';

import '../../../l10n/app_localizations.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/reader_file_type.dart';
import 'ai_api_dialect.dart';
import 'ai_api_family.dart';
import 'ai_endpoint_override.dart';
import 'ai_model_catalog.dart';
import 'ai_operation_routing.dart';
import 'ai_realtime_config.dart';

const int kInferredModelContextWindowTokens = 128000;

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
      inputModalities: stringListFromListValue(json['input_modalities']),
      outputModalities: stringListFromListValue(json['output_modalities']),
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
  agnes('agnes'),
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
      AiProtocolType.agnes => l10n.aiProtocolAgnes,
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
  pptGeneration('ppt_generation'),
  embeddingGeneration('embedding_generation'),
  rerank('rerank'),
  readerConversion('reader_conversion');

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
    this.isGlobalDefaultTitleModel = false,
    this.embeddingDimensions,
    this.embeddingMaxInputTokens,
    this.embeddingSupportsCustomDimensions = false,
    this.embeddingEndpointPath,
    this.embeddingBatchSize,
    this.embeddingRequiresSpecialBody = false,
    this.embeddingQueryModelId,
    this.embeddingDocumentModelId,
    this.embeddingInputTypes = const <String>[],
    this.embeddingDefaultInputType,
    this.embeddingQueryInputType,
    this.embeddingDocumentInputType,
    this.embeddingSupportedTaskTypes = const <String>[],
    this.embeddingDefaultTaskType,
    this.embeddingDefaultQueryTaskType,
    this.embeddingDefaultDocumentTaskType,
    this.embeddingQueryTextPrefix,
    this.embeddingDocumentTextPrefix,
    this.embeddingEncodingFormats = const <String>[],
    this.embeddingDefaultEncodingFormat,
    this.embeddingOutputDTypes = const <String>[],
    this.embeddingDefaultOutputDType,
    this.embeddingDefaultTruncation,
    this.embeddingSimilarityMetric,
    this.embeddingOutputsNormalized,
    this.embeddingMinDimensions,
    this.embeddingMaxDimensions,
    this.embeddingMaxInputsPerBatch,
    this.embeddingMaxTokensPerBatch,
    this.embeddingSupportsTruncation = false,
    this.rerankEndpointPath,
    this.rerankMaxInputTokens,
    this.rerankMaxDocuments,
    this.rerankDefaultTopN,
    this.rerankSupportedParameters = const <String>[],
    this.rerankSupportsReturnDocuments = false,
    this.rerankSupportsInstruction = false,
    this.rerankDefaultInstruction,
    this.rerankSupportsTruncation = false,
    this.rerankDefaultTruncation,
    this.readerSourceTypes = const <String>[],
    this.readerTargetTypes = const <String>[],
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
      architecture: json['architecture'] is Map
          ? AiModelArchitectureMetadata.fromJson(
              stringKeyedMapFromValue(json['architecture']),
            )
          : null,
      supportedParameters: _parseStringList(json['supported_parameters']),
      defaultParameters: _parseObjectMap(json['default_parameters']),
      supportedVoices: _parseStringList(json['supported_voices']),
      knowledgeCutoff: json['knowledge_cutoff'] as String?,
      expirationDate: json['expiration_date'] as String?,
      links: json['links'] is Map
          ? AiModelLinksMetadata.fromJson(
              stringKeyedMapFromValue(json['links']),
            )
          : null,
      isGlobalDefaultTitleModel:
          _readBool(json[_globalDefaultTitleModelJsonKey]) ?? false,
      embeddingDimensions: _readNullablePositiveInt(
        json['embedding_dimensions'],
      ),
      embeddingMaxInputTokens: _readNullablePositiveInt(
        json['embedding_max_input_tokens'],
      ),
      embeddingSupportsCustomDimensions:
          _readBool(json['embedding_supports_custom_dimensions']) ?? false,
      embeddingEndpointPath: json['embedding_endpoint_path'] as String?,
      embeddingBatchSize: _readNullablePositiveInt(
        json['embedding_batch_size'],
      ),
      embeddingRequiresSpecialBody:
          _readBool(json['embedding_requires_special_body']) ?? false,
      embeddingQueryModelId: json['embedding_query_model_id'] as String?,
      embeddingDocumentModelId: json['embedding_document_model_id'] as String?,
      embeddingInputTypes: _parseStringList(json['embedding_input_types']),
      embeddingDefaultInputType:
          json['embedding_default_input_type'] as String?,
      embeddingQueryInputType: json['embedding_query_input_type'] as String?,
      embeddingDocumentInputType:
          json['embedding_document_input_type'] as String?,
      embeddingSupportedTaskTypes: _parseStringList(
        json['embedding_supported_task_types'],
      ),
      embeddingDefaultTaskType: json['embedding_default_task_type'] as String?,
      embeddingDefaultQueryTaskType:
          json['embedding_default_query_task_type'] as String?,
      embeddingDefaultDocumentTaskType:
          json['embedding_default_document_task_type'] as String?,
      embeddingQueryTextPrefix: json['embedding_query_text_prefix'] as String?,
      embeddingDocumentTextPrefix:
          json['embedding_document_text_prefix'] as String?,
      embeddingEncodingFormats: _parseStringList(
        json['embedding_encoding_formats'],
      ),
      embeddingDefaultEncodingFormat:
          json['embedding_default_encoding_format'] as String?,
      embeddingOutputDTypes: _parseStringList(json['embedding_output_dtypes']),
      embeddingDefaultOutputDType:
          json['embedding_default_output_dtype'] as String?,
      embeddingDefaultTruncation:
          json['embedding_default_truncation'] as String?,
      embeddingSimilarityMetric: json['embedding_similarity_metric'] as String?,
      embeddingOutputsNormalized: _readBool(
        json['embedding_outputs_normalized'],
      ),
      embeddingMinDimensions: _readNullablePositiveInt(
        json['embedding_min_dimensions'],
      ),
      embeddingMaxDimensions: _readNullablePositiveInt(
        json['embedding_max_dimensions'],
      ),
      embeddingMaxInputsPerBatch: _readNullablePositiveInt(
        json['embedding_max_inputs_per_batch'],
      ),
      embeddingMaxTokensPerBatch: _readNullablePositiveInt(
        json['embedding_max_tokens_per_batch'],
      ),
      embeddingSupportsTruncation:
          _readBool(json['embedding_supports_truncation']) ?? false,
      rerankEndpointPath: json['rerank_endpoint_path'] as String?,
      rerankMaxInputTokens: _readNullablePositiveInt(
        json['rerank_max_input_tokens'],
      ),
      rerankMaxDocuments: _readNullablePositiveInt(
        json['rerank_max_documents'],
      ),
      rerankDefaultTopN: _readNullablePositiveInt(json['rerank_default_top_n']),
      rerankSupportedParameters: _parseStringList(
        json['rerank_supported_parameters'],
      ),
      rerankSupportsReturnDocuments:
          _readBool(json['rerank_supports_return_documents']) ?? false,
      rerankSupportsInstruction:
          _readBool(json['rerank_supports_instruction']) ?? false,
      rerankDefaultInstruction: json['rerank_default_instruction'] as String?,
      rerankSupportsTruncation:
          _readBool(json['rerank_supports_truncation']) ?? false,
      rerankDefaultTruncation: _readBool(json['rerank_default_truncation']),
      readerSourceTypes: ReaderFileType.normalizeList(
        _parseStringList(json['reader_source_types']),
      ),
      readerTargetTypes: ReaderFileType.normalizeList(
        _parseStringList(json['reader_target_types']),
      ),
    );
  }

  static const String _globalDefaultTitleModelJsonKey =
      'is_global_default_title_model';

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

  /// Whether this concrete model is the app-wide title-generation fallback.
  ///
  /// This belongs to the per-model profile because one provider can expose
  /// text, image, video, and audio models at the same time.
  final bool isGlobalDefaultTitleModel;

  final int? embeddingDimensions;
  final int? embeddingMaxInputTokens;
  final bool embeddingSupportsCustomDimensions;
  final String? embeddingEndpointPath;
  final int? embeddingBatchSize;
  final bool embeddingRequiresSpecialBody;
  final String? embeddingQueryModelId;
  final String? embeddingDocumentModelId;
  final List<String> embeddingInputTypes;
  final String? embeddingDefaultInputType;
  final String? embeddingQueryInputType;
  final String? embeddingDocumentInputType;
  final List<String> embeddingSupportedTaskTypes;
  final String? embeddingDefaultTaskType;
  final String? embeddingDefaultQueryTaskType;
  final String? embeddingDefaultDocumentTaskType;
  final String? embeddingQueryTextPrefix;
  final String? embeddingDocumentTextPrefix;
  final List<String> embeddingEncodingFormats;
  final String? embeddingDefaultEncodingFormat;
  final List<String> embeddingOutputDTypes;
  final String? embeddingDefaultOutputDType;
  final String? embeddingDefaultTruncation;
  final String? embeddingSimilarityMetric;
  final bool? embeddingOutputsNormalized;
  final int? embeddingMinDimensions;
  final int? embeddingMaxDimensions;
  final int? embeddingMaxInputsPerBatch;
  final int? embeddingMaxTokensPerBatch;
  final bool embeddingSupportsTruncation;

  final String? rerankEndpointPath;
  final int? rerankMaxInputTokens;
  final int? rerankMaxDocuments;
  final int? rerankDefaultTopN;
  final List<String> rerankSupportedParameters;
  final bool rerankSupportsReturnDocuments;
  final bool rerankSupportsInstruction;
  final String? rerankDefaultInstruction;
  final bool rerankSupportsTruncation;
  final bool? rerankDefaultTruncation;
  final List<String> readerSourceTypes;
  final List<String> readerTargetTypes;

  bool get supportsEmbeddings =>
      capabilities.contains(AiModelCapability.embeddingGeneration);

  bool get supportsRerank => capabilities.contains(AiModelCapability.rerank);

  bool get supportsReaderConversion =>
      capabilities.contains(AiModelCapability.readerConversion);

  bool supportsReaderSourceType(String sourceType) {
    return supportsReaderConversion &&
        readerSourceTypes.contains(ReaderFileType.normalize(sourceType));
  }

  bool supportsReaderTargetType(String targetType) {
    return supportsReaderConversion &&
        readerTargetTypes.contains(ReaderFileType.normalize(targetType));
  }

  bool supportsReaderConversionFor({
    required String sourceType,
    required String targetType,
  }) {
    return supportsReaderSourceType(sourceType) &&
        supportsReaderTargetType(targetType);
  }

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
      links != null ||
      isGlobalDefaultTitleModel ||
      embeddingDimensions != null ||
      embeddingMaxInputTokens != null ||
      embeddingSupportsCustomDimensions ||
      embeddingEndpointPath != null ||
      embeddingBatchSize != null ||
      embeddingRequiresSpecialBody ||
      embeddingQueryModelId != null ||
      embeddingDocumentModelId != null ||
      embeddingInputTypes.isNotEmpty ||
      embeddingDefaultInputType != null ||
      embeddingQueryInputType != null ||
      embeddingDocumentInputType != null ||
      embeddingSupportedTaskTypes.isNotEmpty ||
      embeddingDefaultTaskType != null ||
      embeddingDefaultQueryTaskType != null ||
      embeddingDefaultDocumentTaskType != null ||
      embeddingQueryTextPrefix != null ||
      embeddingDocumentTextPrefix != null ||
      embeddingEncodingFormats.isNotEmpty ||
      embeddingDefaultEncodingFormat != null ||
      embeddingOutputDTypes.isNotEmpty ||
      embeddingDefaultOutputDType != null ||
      embeddingDefaultTruncation != null ||
      embeddingSimilarityMetric != null ||
      embeddingOutputsNormalized != null ||
      embeddingMinDimensions != null ||
      embeddingMaxDimensions != null ||
      embeddingMaxInputsPerBatch != null ||
      embeddingMaxTokensPerBatch != null ||
      embeddingSupportsTruncation ||
      rerankEndpointPath != null ||
      rerankMaxInputTokens != null ||
      rerankMaxDocuments != null ||
      rerankDefaultTopN != null ||
      rerankSupportedParameters.isNotEmpty ||
      rerankSupportsReturnDocuments ||
      rerankSupportsInstruction ||
      rerankDefaultInstruction != null ||
      rerankSupportsTruncation ||
      rerankDefaultTruncation != null ||
      readerSourceTypes.isNotEmpty ||
      readerTargetTypes.isNotEmpty;

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
    bool? isGlobalDefaultTitleModel,
    int? embeddingDimensions,
    bool clearEmbeddingDimensions = false,
    int? embeddingMaxInputTokens,
    bool clearEmbeddingMaxInputTokens = false,
    bool? embeddingSupportsCustomDimensions,
    String? embeddingEndpointPath,
    bool clearEmbeddingEndpointPath = false,
    int? embeddingBatchSize,
    bool clearEmbeddingBatchSize = false,
    bool? embeddingRequiresSpecialBody,
    String? embeddingQueryModelId,
    bool clearEmbeddingQueryModelId = false,
    String? embeddingDocumentModelId,
    bool clearEmbeddingDocumentModelId = false,
    List<String>? embeddingInputTypes,
    String? embeddingDefaultInputType,
    bool clearEmbeddingDefaultInputType = false,
    String? embeddingQueryInputType,
    bool clearEmbeddingQueryInputType = false,
    String? embeddingDocumentInputType,
    bool clearEmbeddingDocumentInputType = false,
    List<String>? embeddingSupportedTaskTypes,
    String? embeddingDefaultTaskType,
    bool clearEmbeddingDefaultTaskType = false,
    String? embeddingDefaultQueryTaskType,
    bool clearEmbeddingDefaultQueryTaskType = false,
    String? embeddingDefaultDocumentTaskType,
    bool clearEmbeddingDefaultDocumentTaskType = false,
    String? embeddingQueryTextPrefix,
    bool clearEmbeddingQueryTextPrefix = false,
    String? embeddingDocumentTextPrefix,
    bool clearEmbeddingDocumentTextPrefix = false,
    List<String>? embeddingEncodingFormats,
    String? embeddingDefaultEncodingFormat,
    bool clearEmbeddingDefaultEncodingFormat = false,
    List<String>? embeddingOutputDTypes,
    String? embeddingDefaultOutputDType,
    bool clearEmbeddingDefaultOutputDType = false,
    String? embeddingDefaultTruncation,
    bool clearEmbeddingDefaultTruncation = false,
    String? embeddingSimilarityMetric,
    bool clearEmbeddingSimilarityMetric = false,
    bool? embeddingOutputsNormalized,
    bool clearEmbeddingOutputsNormalized = false,
    int? embeddingMinDimensions,
    bool clearEmbeddingMinDimensions = false,
    int? embeddingMaxDimensions,
    bool clearEmbeddingMaxDimensions = false,
    int? embeddingMaxInputsPerBatch,
    bool clearEmbeddingMaxInputsPerBatch = false,
    int? embeddingMaxTokensPerBatch,
    bool clearEmbeddingMaxTokensPerBatch = false,
    bool? embeddingSupportsTruncation,
    String? rerankEndpointPath,
    bool clearRerankEndpointPath = false,
    int? rerankMaxInputTokens,
    bool clearRerankMaxInputTokens = false,
    int? rerankMaxDocuments,
    bool clearRerankMaxDocuments = false,
    int? rerankDefaultTopN,
    bool clearRerankDefaultTopN = false,
    List<String>? rerankSupportedParameters,
    bool? rerankSupportsReturnDocuments,
    bool? rerankSupportsInstruction,
    String? rerankDefaultInstruction,
    bool clearRerankDefaultInstruction = false,
    bool? rerankSupportsTruncation,
    bool? rerankDefaultTruncation,
    bool clearRerankDefaultTruncation = false,
    List<String>? readerSourceTypes,
    List<String>? readerTargetTypes,
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
      isGlobalDefaultTitleModel:
          isGlobalDefaultTitleModel ?? this.isGlobalDefaultTitleModel,
      embeddingDimensions: clearEmbeddingDimensions
          ? null
          : embeddingDimensions ?? this.embeddingDimensions,
      embeddingMaxInputTokens: clearEmbeddingMaxInputTokens
          ? null
          : embeddingMaxInputTokens ?? this.embeddingMaxInputTokens,
      embeddingSupportsCustomDimensions:
          embeddingSupportsCustomDimensions ??
          this.embeddingSupportsCustomDimensions,
      embeddingEndpointPath: clearEmbeddingEndpointPath
          ? null
          : embeddingEndpointPath ?? this.embeddingEndpointPath,
      embeddingBatchSize: clearEmbeddingBatchSize
          ? null
          : embeddingBatchSize ?? this.embeddingBatchSize,
      embeddingRequiresSpecialBody:
          embeddingRequiresSpecialBody ?? this.embeddingRequiresSpecialBody,
      embeddingQueryModelId: clearEmbeddingQueryModelId
          ? null
          : embeddingQueryModelId ?? this.embeddingQueryModelId,
      embeddingDocumentModelId: clearEmbeddingDocumentModelId
          ? null
          : embeddingDocumentModelId ?? this.embeddingDocumentModelId,
      embeddingInputTypes: embeddingInputTypes ?? this.embeddingInputTypes,
      embeddingDefaultInputType: clearEmbeddingDefaultInputType
          ? null
          : embeddingDefaultInputType ?? this.embeddingDefaultInputType,
      embeddingQueryInputType: clearEmbeddingQueryInputType
          ? null
          : embeddingQueryInputType ?? this.embeddingQueryInputType,
      embeddingDocumentInputType: clearEmbeddingDocumentInputType
          ? null
          : embeddingDocumentInputType ?? this.embeddingDocumentInputType,
      embeddingSupportedTaskTypes:
          embeddingSupportedTaskTypes ?? this.embeddingSupportedTaskTypes,
      embeddingDefaultTaskType: clearEmbeddingDefaultTaskType
          ? null
          : embeddingDefaultTaskType ?? this.embeddingDefaultTaskType,
      embeddingDefaultQueryTaskType: clearEmbeddingDefaultQueryTaskType
          ? null
          : embeddingDefaultQueryTaskType ?? this.embeddingDefaultQueryTaskType,
      embeddingDefaultDocumentTaskType: clearEmbeddingDefaultDocumentTaskType
          ? null
          : embeddingDefaultDocumentTaskType ??
                this.embeddingDefaultDocumentTaskType,
      embeddingQueryTextPrefix: clearEmbeddingQueryTextPrefix
          ? null
          : embeddingQueryTextPrefix ?? this.embeddingQueryTextPrefix,
      embeddingDocumentTextPrefix: clearEmbeddingDocumentTextPrefix
          ? null
          : embeddingDocumentTextPrefix ?? this.embeddingDocumentTextPrefix,
      embeddingEncodingFormats:
          embeddingEncodingFormats ?? this.embeddingEncodingFormats,
      embeddingDefaultEncodingFormat: clearEmbeddingDefaultEncodingFormat
          ? null
          : embeddingDefaultEncodingFormat ??
                this.embeddingDefaultEncodingFormat,
      embeddingOutputDTypes:
          embeddingOutputDTypes ?? this.embeddingOutputDTypes,
      embeddingDefaultOutputDType: clearEmbeddingDefaultOutputDType
          ? null
          : embeddingDefaultOutputDType ?? this.embeddingDefaultOutputDType,
      embeddingDefaultTruncation: clearEmbeddingDefaultTruncation
          ? null
          : embeddingDefaultTruncation ?? this.embeddingDefaultTruncation,
      embeddingSimilarityMetric: clearEmbeddingSimilarityMetric
          ? null
          : embeddingSimilarityMetric ?? this.embeddingSimilarityMetric,
      embeddingOutputsNormalized: clearEmbeddingOutputsNormalized
          ? null
          : embeddingOutputsNormalized ?? this.embeddingOutputsNormalized,
      embeddingMinDimensions: clearEmbeddingMinDimensions
          ? null
          : embeddingMinDimensions ?? this.embeddingMinDimensions,
      embeddingMaxDimensions: clearEmbeddingMaxDimensions
          ? null
          : embeddingMaxDimensions ?? this.embeddingMaxDimensions,
      embeddingMaxInputsPerBatch: clearEmbeddingMaxInputsPerBatch
          ? null
          : embeddingMaxInputsPerBatch ?? this.embeddingMaxInputsPerBatch,
      embeddingMaxTokensPerBatch: clearEmbeddingMaxTokensPerBatch
          ? null
          : embeddingMaxTokensPerBatch ?? this.embeddingMaxTokensPerBatch,
      embeddingSupportsTruncation:
          embeddingSupportsTruncation ?? this.embeddingSupportsTruncation,
      rerankEndpointPath: clearRerankEndpointPath
          ? null
          : rerankEndpointPath ?? this.rerankEndpointPath,
      rerankMaxInputTokens: clearRerankMaxInputTokens
          ? null
          : rerankMaxInputTokens ?? this.rerankMaxInputTokens,
      rerankMaxDocuments: clearRerankMaxDocuments
          ? null
          : rerankMaxDocuments ?? this.rerankMaxDocuments,
      rerankDefaultTopN: clearRerankDefaultTopN
          ? null
          : rerankDefaultTopN ?? this.rerankDefaultTopN,
      rerankSupportedParameters:
          rerankSupportedParameters ?? this.rerankSupportedParameters,
      rerankSupportsReturnDocuments:
          rerankSupportsReturnDocuments ?? this.rerankSupportsReturnDocuments,
      rerankSupportsInstruction:
          rerankSupportsInstruction ?? this.rerankSupportsInstruction,
      rerankDefaultInstruction: clearRerankDefaultInstruction
          ? null
          : rerankDefaultInstruction ?? this.rerankDefaultInstruction,
      rerankSupportsTruncation:
          rerankSupportsTruncation ?? this.rerankSupportsTruncation,
      rerankDefaultTruncation: clearRerankDefaultTruncation
          ? null
          : rerankDefaultTruncation ?? this.rerankDefaultTruncation,
      readerSourceTypes: readerSourceTypes ?? this.readerSourceTypes,
      readerTargetTypes: readerTargetTypes ?? this.readerTargetTypes,
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
      if (isGlobalDefaultTitleModel) _globalDefaultTitleModelJsonKey: true,
      if (embeddingDimensions != null)
        'embedding_dimensions': embeddingDimensions,
      if (embeddingMaxInputTokens != null)
        'embedding_max_input_tokens': embeddingMaxInputTokens,
      if (embeddingSupportsCustomDimensions)
        'embedding_supports_custom_dimensions': true,
      if (embeddingEndpointPath != null)
        'embedding_endpoint_path': embeddingEndpointPath,
      if (embeddingBatchSize != null)
        'embedding_batch_size': embeddingBatchSize,
      if (embeddingRequiresSpecialBody) 'embedding_requires_special_body': true,
      if (embeddingQueryModelId != null)
        'embedding_query_model_id': embeddingQueryModelId,
      if (embeddingDocumentModelId != null)
        'embedding_document_model_id': embeddingDocumentModelId,
      if (embeddingInputTypes.isNotEmpty)
        'embedding_input_types': embeddingInputTypes,
      if (embeddingDefaultInputType != null)
        'embedding_default_input_type': embeddingDefaultInputType,
      if (embeddingQueryInputType != null)
        'embedding_query_input_type': embeddingQueryInputType,
      if (embeddingDocumentInputType != null)
        'embedding_document_input_type': embeddingDocumentInputType,
      if (embeddingSupportedTaskTypes.isNotEmpty)
        'embedding_supported_task_types': embeddingSupportedTaskTypes,
      if (embeddingDefaultTaskType != null)
        'embedding_default_task_type': embeddingDefaultTaskType,
      if (embeddingDefaultQueryTaskType != null)
        'embedding_default_query_task_type': embeddingDefaultQueryTaskType,
      if (embeddingDefaultDocumentTaskType != null)
        'embedding_default_document_task_type':
            embeddingDefaultDocumentTaskType,
      if (embeddingQueryTextPrefix != null)
        'embedding_query_text_prefix': embeddingQueryTextPrefix,
      if (embeddingDocumentTextPrefix != null)
        'embedding_document_text_prefix': embeddingDocumentTextPrefix,
      if (embeddingEncodingFormats.isNotEmpty)
        'embedding_encoding_formats': embeddingEncodingFormats,
      if (embeddingDefaultEncodingFormat != null)
        'embedding_default_encoding_format': embeddingDefaultEncodingFormat,
      if (embeddingOutputDTypes.isNotEmpty)
        'embedding_output_dtypes': embeddingOutputDTypes,
      if (embeddingDefaultOutputDType != null)
        'embedding_default_output_dtype': embeddingDefaultOutputDType,
      if (embeddingDefaultTruncation != null)
        'embedding_default_truncation': embeddingDefaultTruncation,
      if (embeddingSimilarityMetric != null)
        'embedding_similarity_metric': embeddingSimilarityMetric,
      if (embeddingOutputsNormalized != null)
        'embedding_outputs_normalized': embeddingOutputsNormalized,
      if (embeddingMinDimensions != null)
        'embedding_min_dimensions': embeddingMinDimensions,
      if (embeddingMaxDimensions != null)
        'embedding_max_dimensions': embeddingMaxDimensions,
      if (embeddingMaxInputsPerBatch != null)
        'embedding_max_inputs_per_batch': embeddingMaxInputsPerBatch,
      if (embeddingMaxTokensPerBatch != null)
        'embedding_max_tokens_per_batch': embeddingMaxTokensPerBatch,
      if (embeddingSupportsTruncation) 'embedding_supports_truncation': true,
      if (rerankEndpointPath != null)
        'rerank_endpoint_path': rerankEndpointPath,
      if (rerankMaxInputTokens != null)
        'rerank_max_input_tokens': rerankMaxInputTokens,
      if (rerankMaxDocuments != null)
        'rerank_max_documents': rerankMaxDocuments,
      if (rerankDefaultTopN != null) 'rerank_default_top_n': rerankDefaultTopN,
      if (rerankSupportedParameters.isNotEmpty)
        'rerank_supported_parameters': rerankSupportedParameters,
      if (rerankSupportsReturnDocuments)
        'rerank_supports_return_documents': true,
      if (rerankSupportsInstruction) 'rerank_supports_instruction': true,
      if (rerankDefaultInstruction != null)
        'rerank_default_instruction': rerankDefaultInstruction,
      if (rerankSupportsTruncation) 'rerank_supports_truncation': true,
      if (rerankDefaultTruncation != null)
        'rerank_default_truncation': rerankDefaultTruncation,
      if (readerSourceTypes.isNotEmpty)
        'reader_source_types': readerSourceTypes,
      if (readerTargetTypes.isNotEmpty)
        'reader_target_types': readerTargetTypes,
    };
  }

  static Set<AiModelModality> _parseModalities(Object? value) {
    final result = <AiModelModality>{};
    for (final item in stringListFromListValue(value)) {
      final m = AiModelModality.fromStorage(item);
      if (m != null) result.add(m);
    }
    return result;
  }

  static Set<AiModelCapability> _parseCapabilities(Object? value) {
    final result = <AiModelCapability>{};
    for (final item in stringListFromListValue(value)) {
      final c = AiModelCapability.fromStorage(item);
      if (c != null) result.add(c);
    }
    return result;
  }

  static List<String> _parseStringList(Object? value) {
    return stringListFromListValue(value);
  }

  static Map<String, Object?> _parseObjectMap(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.of(stringKeyedMapFromValue(value));
    }
    return const <String, Object?>{};
  }

  static int? _readNullableInt(Object? value) {
    return optionalIntFromValue(value);
  }

  static int? _readNullablePositiveInt(Object? value) {
    return optionalPositiveIntFromValue(value);
  }

  static double? _readNullableNonNegativeDouble(Object? value) {
    return optionalNonNegativeDoubleFromValue(value);
  }

  static bool? _readBool(Object? value) {
    return optionalBoolFromValue(value);
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
    final apiDialect = rawApiDialect.isEmpty
        ? inferAiApiDialect(protocolType)
        : AiApiDialect.fromStorage(rawApiDialect);
    final providerKind = rawProviderKind.isEmpty
        ? inferAiProviderKind(protocolType)
        : AiProviderKind.fromStorage(rawProviderKind);
    return AiModelConfig(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      officialWebsiteUrl: _readOfficialWebsiteUrl(json),
      baseUrl: _normalizeBaseUrl('${json['base_url'] ?? ''}'),
      autoCompleteBaseUrl: _readBool(json[_autoCompleteBaseUrlJsonKey]) ?? true,
      authScheme: AiAuthScheme.fromStorage('${json['auth_scheme'] ?? ''}'),
      token: '${json['token'] ?? ''}',
      modelId: '${json['model_id'] ?? ''}'.trim(),
      protocolType: protocolType,
      apiDialect: apiDialect,
      providerKind: providerKind,
      explicitPromptCacheEnabled: _readExplicitPromptCacheEnabled(
        protocolType: protocolType,
        value: json[_explicitPromptCacheEnabledJsonKey],
      ),
      maxContextTokens: _readNullablePositiveInt(json['max_context_tokens']),
      availableModelIds: availableModelIds,
      defaultTitleModelId: '${json['default_title_model_id'] ?? ''}'.trim(),
      isGlobalDefaultTitleModel:
          _readBool(json['is_global_default_title_model']) ?? false,
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
    this.officialWebsiteUrl = '',
    required this.baseUrl,
    this.autoCompleteBaseUrl = true,
    required this.authScheme,
    required this.token,
    required this.modelId,
    required this.protocolType,
    this.apiDialect = AiApiDialect.openAiCompat,
    this.providerKind = AiProviderKind.custom,
    bool? explicitPromptCacheEnabled,
    this.maxContextTokens,
    this.availableModelIds = const <String>[],
    this.defaultTitleModelId = '',
    this.isGlobalDefaultTitleModel = false,
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
  }) : explicitPromptCacheEnabled =
           protocolType == AiProtocolType.claude &&
           (explicitPromptCacheEnabled ?? true);

  static final RegExp _reasoningModelIdSeparatorPattern = RegExp(r'[^a-z0-9]+');
  static final RegExp _reasoningModelIdRepeatedDashPattern = RegExp(r'-+');
  static final RegExp _reasoningModelIdEdgeDashPattern = RegExp(r'^-|-$');
  static final RegExp _officialWebsiteWhitespacePattern = RegExp(r'\s');
  static const Set<String> _deepSeekPlainChatModelIds = <String>{
    'deepseek-chat',
  };

  static const String _explicitPromptCacheEnabledJsonKey =
      'explicit_prompt_cache_enabled';
  static const String _autoCompleteBaseUrlJsonKey = 'auto_complete_base_url';
  static const String _officialWebsiteUrlJsonKey = 'official_website_url';

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

  /// Optional provider homepage shown in settings. Only valid http(s) values
  /// are surfaced to UI actions.
  final String officialWebsiteUrl;

  final String baseUrl;
  final bool autoCompleteBaseUrl;
  final AiAuthScheme authScheme;
  final String token;

  /// The currently active model ID for this provider.
  final String modelId;
  final AiProtocolType protocolType;
  final AiApiDialect apiDialect;
  final AiProviderKind providerKind;

  /// Claude native prompt-cache markers are opt-in at provider level and are
  /// still gated by the global cost-control input-cache switch at runtime.
  final bool explicitPromptCacheEnabled;

  final int? maxContextTokens;

  /// All known model IDs for this provider (auto-scanned + manually added).
  final List<String> availableModelIds;

  /// Provider-level fallback model used only for session title generation.
  ///
  /// This lets non-text generation models (image / video / audio) keep using
  /// their own provider credentials while delegating title synthesis to a
  /// text-capable sibling model from the same provider.
  final String defaultTitleModelId;

  /// Legacy provider-level app-wide title fallback marker.
  ///
  /// New UI writes this setting to [AiModelProfile.isGlobalDefaultTitleModel]
  /// because the fallback belongs to one concrete text-capable model. This
  /// field remains readable so older settings files keep working.
  final bool isGlobalDefaultTitleModel;

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
      isGlobalDefaultTitleModel: override.isGlobalDefaultTitleModel,
      embeddingDimensions:
          override.embeddingDimensions ?? catalog.embeddingDimensions,
      embeddingMaxInputTokens:
          override.embeddingMaxInputTokens ?? catalog.embeddingMaxInputTokens,
      embeddingSupportsCustomDimensions:
          override.embeddingSupportsCustomDimensions ||
          catalog.embeddingSupportsCustomDimensions,
      embeddingEndpointPath:
          override.embeddingEndpointPath ?? catalog.embeddingEndpointPath,
      embeddingBatchSize:
          override.embeddingBatchSize ?? catalog.embeddingBatchSize,
      embeddingRequiresSpecialBody:
          override.embeddingRequiresSpecialBody ||
          catalog.embeddingRequiresSpecialBody,
      embeddingQueryModelId:
          override.embeddingQueryModelId ?? catalog.embeddingQueryModelId,
      embeddingDocumentModelId:
          override.embeddingDocumentModelId ?? catalog.embeddingDocumentModelId,
      embeddingInputTypes: override.embeddingInputTypes.isNotEmpty
          ? override.embeddingInputTypes
          : catalog.embeddingInputTypes,
      embeddingDefaultInputType:
          override.embeddingDefaultInputType ??
          catalog.embeddingDefaultInputType,
      embeddingQueryInputType:
          override.embeddingQueryInputType ?? catalog.embeddingQueryInputType,
      embeddingDocumentInputType:
          override.embeddingDocumentInputType ??
          catalog.embeddingDocumentInputType,
      embeddingSupportedTaskTypes:
          override.embeddingSupportedTaskTypes.isNotEmpty
          ? override.embeddingSupportedTaskTypes
          : catalog.embeddingSupportedTaskTypes,
      embeddingDefaultTaskType:
          override.embeddingDefaultTaskType ?? catalog.embeddingDefaultTaskType,
      embeddingDefaultQueryTaskType:
          override.embeddingDefaultQueryTaskType ??
          catalog.embeddingDefaultQueryTaskType,
      embeddingDefaultDocumentTaskType:
          override.embeddingDefaultDocumentTaskType ??
          catalog.embeddingDefaultDocumentTaskType,
      embeddingQueryTextPrefix:
          override.embeddingQueryTextPrefix ?? catalog.embeddingQueryTextPrefix,
      embeddingDocumentTextPrefix:
          override.embeddingDocumentTextPrefix ??
          catalog.embeddingDocumentTextPrefix,
      embeddingEncodingFormats: override.embeddingEncodingFormats.isNotEmpty
          ? override.embeddingEncodingFormats
          : catalog.embeddingEncodingFormats,
      embeddingDefaultEncodingFormat:
          override.embeddingDefaultEncodingFormat ??
          catalog.embeddingDefaultEncodingFormat,
      embeddingOutputDTypes: override.embeddingOutputDTypes.isNotEmpty
          ? override.embeddingOutputDTypes
          : catalog.embeddingOutputDTypes,
      embeddingDefaultOutputDType:
          override.embeddingDefaultOutputDType ??
          catalog.embeddingDefaultOutputDType,
      embeddingDefaultTruncation:
          override.embeddingDefaultTruncation ??
          catalog.embeddingDefaultTruncation,
      embeddingSimilarityMetric:
          override.embeddingSimilarityMetric ??
          catalog.embeddingSimilarityMetric,
      embeddingOutputsNormalized:
          override.embeddingOutputsNormalized ??
          catalog.embeddingOutputsNormalized,
      embeddingMinDimensions:
          override.embeddingMinDimensions ?? catalog.embeddingMinDimensions,
      embeddingMaxDimensions:
          override.embeddingMaxDimensions ?? catalog.embeddingMaxDimensions,
      embeddingMaxInputsPerBatch:
          override.embeddingMaxInputsPerBatch ??
          catalog.embeddingMaxInputsPerBatch,
      embeddingMaxTokensPerBatch:
          override.embeddingMaxTokensPerBatch ??
          catalog.embeddingMaxTokensPerBatch,
      embeddingSupportsTruncation:
          override.embeddingSupportsTruncation ||
          catalog.embeddingSupportsTruncation,
      rerankEndpointPath:
          override.rerankEndpointPath ?? catalog.rerankEndpointPath,
      rerankMaxInputTokens:
          override.rerankMaxInputTokens ?? catalog.rerankMaxInputTokens,
      rerankMaxDocuments:
          override.rerankMaxDocuments ?? catalog.rerankMaxDocuments,
      rerankDefaultTopN:
          override.rerankDefaultTopN ?? catalog.rerankDefaultTopN,
      rerankSupportedParameters: override.rerankSupportedParameters.isNotEmpty
          ? override.rerankSupportedParameters
          : catalog.rerankSupportedParameters,
      rerankSupportsReturnDocuments:
          override.rerankSupportsReturnDocuments ||
          catalog.rerankSupportsReturnDocuments,
      rerankSupportsInstruction:
          override.rerankSupportsInstruction ||
          catalog.rerankSupportsInstruction,
      rerankDefaultInstruction:
          override.rerankDefaultInstruction ?? catalog.rerankDefaultInstruction,
      rerankSupportsTruncation:
          override.rerankSupportsTruncation || catalog.rerankSupportsTruncation,
      rerankDefaultTruncation:
          override.rerankDefaultTruncation ?? catalog.rerankDefaultTruncation,
      readerSourceTypes: override.readerSourceTypes.isNotEmpty
          ? override.readerSourceTypes
          : catalog.readerSourceTypes,
      readerTargetTypes: override.readerTargetTypes.isNotEmpty
          ? override.readerTargetTypes
          : catalog.readerTargetTypes,
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

  bool get supportsExplicitPromptCacheControl =>
      protocolType == AiProtocolType.claude;

  bool get effectiveExplicitPromptCacheEnabled =>
      supportsExplicitPromptCacheControl && explicitPromptCacheEnabled;

  bool get requiresReasoningEcho {
    final trimmedModelId = modelId.trim();
    final userOverride = modelProfiles[trimmedModelId]?.requiresReasoningEcho;
    if (userOverride != null) {
      return userOverride;
    }
    final profile = profileFor(trimmedModelId);
    final catalogProfile = AiModelCatalog.lookup(trimmedModelId, protocolType);
    final catalogEcho = catalogProfile?.requiresReasoningEcho;
    if (catalogEcho == true) {
      return true;
    }
    final normalizedModelId = _normalizeReasoningModelId(trimmedModelId);
    if (normalizedModelId.isEmpty) {
      return false;
    }
    if (_usesDeepSeekReasoningGateway &&
        _shouldEchoDeepSeekReasoning(
          normalizedModelId: normalizedModelId,
          profile: profile,
        )) {
      return true;
    }
    if (catalogEcho != null) {
      return catalogEcho;
    }
    if (_looksLikeDeepSeekReasoningModel(normalizedModelId)) {
      return true;
    }
    return false;
  }

  bool get _usesDeepSeekReasoningGateway =>
      protocolType == AiProtocolType.deepseek ||
      _containsDeepSeekMarker(baseUrl) ||
      _containsDeepSeekMarker(name);

  static bool _containsDeepSeekMarker(String value) {
    return value.toLowerCase().contains('deepseek');
  }

  static String _normalizeReasoningModelId(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(_reasoningModelIdSeparatorPattern, '-')
        .replaceAll(_reasoningModelIdRepeatedDashPattern, '-')
        .replaceAll(_reasoningModelIdEdgeDashPattern, '');
  }

  static bool _shouldEchoDeepSeekReasoning({
    required String normalizedModelId,
    required AiModelProfile profile,
  }) {
    if (_deepSeekPlainChatModelIds.contains(normalizedModelId)) {
      return false;
    }
    return _looksLikeDeepSeekReasoningModel(normalizedModelId) ||
        _looksLikeDeepSeekHybridThinkingModel(normalizedModelId) ||
        (profile.maxThinkingLength ?? 0) > 0;
  }

  static bool _looksLikeDeepSeekHybridThinkingModel(String normalizedModelId) {
    return normalizedModelId.contains('deepseek-v3-1') ||
        normalizedModelId.contains('deepseek-v3-2');
  }

  static bool _looksLikeDeepSeekReasoningModel(String normalizedModelId) {
    return normalizedModelId.startsWith('deepseek-reasoner') ||
        normalizedModelId.contains('deepseek-reasoner') ||
        normalizedModelId.startsWith('deepseek-r1') ||
        normalizedModelId.contains('deepseek-r1') ||
        normalizedModelId.startsWith('deepseek-v4') ||
        normalizedModelId.contains('deepseek-v4') ||
        (normalizedModelId.contains('deepseek') &&
            (normalizedModelId.contains('reasoner') ||
                normalizedModelId.contains('thinking') ||
                normalizedModelId.contains('think')));
  }

  String get normalizedBaseUrl => _normalizeBaseUrl(baseUrl);

  Uri? get officialWebsiteUri => _parseOfficialWebsiteUri(officialWebsiteUrl);

  String get normalizedOfficialWebsiteUrl =>
      officialWebsiteUri?.toString() ?? '';

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
      if (defaultTitleModelId.trim().isNotEmpty) defaultTitleModelId.trim(),
    ]);
  }

  AiModelConfig copyWith({
    String? id,
    String? name,
    String? officialWebsiteUrl,
    String? baseUrl,
    bool? autoCompleteBaseUrl,
    AiAuthScheme? authScheme,
    String? token,
    String? modelId,
    AiProtocolType? protocolType,
    AiApiDialect? apiDialect,
    AiProviderKind? providerKind,
    bool? explicitPromptCacheEnabled,
    int? maxContextTokens,
    bool clearMaxContextTokens = false,
    List<String>? availableModelIds,
    String? defaultTitleModelId,
    bool? isGlobalDefaultTitleModel,
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
      officialWebsiteUrl: _normalizeOfficialWebsiteUrl(
        officialWebsiteUrl ?? this.officialWebsiteUrl,
      ),
      baseUrl: _normalizeBaseUrl(baseUrl ?? this.baseUrl),
      autoCompleteBaseUrl: autoCompleteBaseUrl ?? this.autoCompleteBaseUrl,
      authScheme: authScheme ?? this.authScheme,
      token: token ?? this.token,
      modelId: modelId ?? this.modelId,
      protocolType: protocolType ?? this.protocolType,
      apiDialect: apiDialect ?? this.apiDialect,
      providerKind: providerKind ?? this.providerKind,
      explicitPromptCacheEnabled:
          explicitPromptCacheEnabled ?? this.explicitPromptCacheEnabled,
      maxContextTokens: clearMaxContextTokens
          ? null
          : maxContextTokens ?? this.maxContextTokens,
      availableModelIds: normalizeModelIds(
        availableModelIds ?? this.availableModelIds,
      ),
      defaultTitleModelId: defaultTitleModelId ?? this.defaultTitleModelId,
      isGlobalDefaultTitleModel:
          isGlobalDefaultTitleModel ?? this.isGlobalDefaultTitleModel,
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
      if (normalizedOfficialWebsiteUrl.isNotEmpty)
        _officialWebsiteUrlJsonKey: normalizedOfficialWebsiteUrl,
      'base_url': normalizedBaseUrl,
      _autoCompleteBaseUrlJsonKey: autoCompleteBaseUrl,
      'auth_scheme': authScheme.storageValue,
      'token': token,
      'model_id': modelId.trim(),
      'protocol_type': protocolType.storageValue,
      'api_dialect': apiDialect.storageValue,
      'provider_kind': providerKind.storageValue,
      if (supportsExplicitPromptCacheControl)
        _explicitPromptCacheEnabledJsonKey: effectiveExplicitPromptCacheEnabled,
      'max_context_tokens': maxContextTokens,
      'available_model_ids': normalizeModelIds(availableModelIds),
      if (defaultTitleModelId.trim().isNotEmpty)
        'default_title_model_id': defaultTitleModelId.trim(),
      if (isGlobalDefaultTitleModel) 'is_global_default_title_model': true,
      'custom_headers': customHeaders,
      'request_method': requestMethod,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'stream_enabled': streamEnabled,
      if (profilesJson.isNotEmpty) 'model_profiles': profilesJson,
      if (endpointOverridesJson.isNotEmpty)
        'endpoint_overrides': endpointOverridesJson,
      if (!operationRouting.isEmpty)
        'operation_routing': operationRouting.toJson(),
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

  static Uri? _parseOfficialWebsiteUri(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty ||
        _officialWebsiteWhitespacePattern.hasMatch(trimmedValue)) {
      return null;
    }
    final uri = Uri.tryParse(trimmedValue);
    if (uri == null || !uri.hasScheme) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    if (uri.host.trim().isEmpty || uri.userInfo.trim().isNotEmpty) {
      return null;
    }
    return uri.scheme == scheme ? uri : uri.replace(scheme: scheme);
  }

  static String _normalizeOfficialWebsiteUrl(String value) {
    return _parseOfficialWebsiteUri(value)?.toString() ?? '';
  }

  static String _readOfficialWebsiteUrl(Map<String, Object?> json) {
    for (final key in const <String>[
      _officialWebsiteUrlJsonKey,
      'website_url',
      'official_url',
    ]) {
      final normalized = _normalizeOfficialWebsiteUrl('${json[key] ?? ''}');
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  static bool? _readBool(Object? value) {
    return optionalBoolFromValue(value);
  }

  static int? _readNullablePositiveInt(Object? value) {
    return optionalPositiveIntFromValue(value);
  }

  static bool _readExplicitPromptCacheEnabled({
    required AiProtocolType protocolType,
    required Object? value,
  }) {
    final supported = protocolType == AiProtocolType.claude;
    if (!supported) {
      return false;
    }
    return value is bool ? value : true;
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
    return optionalDoubleFromValue(value);
  }

  static String _parseRequestMethod(Object? value) {
    final raw = '${value ?? ''}'.trim().toUpperCase();
    if (raw.isEmpty) return 'POST';
    return raw;
  }

  static Map<String, AiModelProfile> _parseModelProfiles(Object? value) {
    if (value == null) return const <String, AiModelProfile>{};
    Map<String, Object?>? map;
    if (value is Map) {
      map = stringKeyedMapFromValue(value);
    } else if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return const <String, AiModelProfile>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          map = stringKeyedMapFromValue(decoded);
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
          stringKeyedMapFromValue(entry.value),
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
    if (value is Map) {
      return Map<String, Object?>.of(stringKeyedMapFromValue(value));
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return const <String, Object?>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return Map<String, Object?>.of(stringKeyedMapFromValue(decoded));
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
