import 'dart:convert';

import '../../../l10n/app_localizations.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/reader_file_type.dart';
import 'ai_api_dialect.dart';
import 'ai_api_family.dart';
import 'ai_endpoint_override.dart';
import 'ai_model_catalog.dart';
import 'ai_one_million_context_policy.dart';
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
      modality: json['modality'] is String ? json['modality'] as String : null,
      inputModalities: stringListFromListValue(json['input_modalities']),
      outputModalities: stringListFromListValue(json['output_modalities']),
      tokenizer: json['tokenizer'] is String
          ? json['tokenizer'] as String
          : null,
      instructType: json['instruct_type'] is String
          ? json['instruct_type'] as String
          : null,
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
    return AiModelLinksMetadata(
      details: optionalStringFromValue(json['details']),
    );
  }

  final String? details;

  bool get isEmpty => nullIfBlank(details) == null;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    putIfNotBlank(json, 'details', details);
    return json;
  }
}

class AiReasoningEffortOption {
  const AiReasoningEffortOption({
    required this.value,
    required this.label,
    this.enabled = true,
    this.labelZhHans,
    this.labelZhHant,
    this.labelEn,
    this.labelFr,
    this.labelDe,
    this.labelJa,
  });

  factory AiReasoningEffortOption.fromJson(Map<String, Object?> json) {
    final value = stringFromValue(json['value']).trim();
    return AiReasoningEffortOption(
      value: value,
      label: _readLabel(json),
      enabled: optionalBoolFromValue(json['enabled']) ?? true,
      labelZhHans: optionalStringFromValue(json['label_zh_hans']),
      labelZhHant: optionalStringFromValue(json['label_zh_hant']),
      labelEn: optionalStringFromValue(json['label_en']),
      labelFr: optionalStringFromValue(json['label_fr']),
      labelDe: optionalStringFromValue(json['label_de']),
      labelJa: optionalStringFromValue(json['label_ja']),
    );
  }

  static const _none = AiReasoningEffortOption(
    value: 'none',
    label: '无',
    labelZhHans: '无',
    labelZhHant: '無',
    labelEn: 'None',
    labelFr: 'Aucun',
    labelDe: 'Keine',
    labelJa: 'なし',
  );
  static const _minimal = AiReasoningEffortOption(
    value: 'minimal',
    label: '极低',
    labelZhHans: '极低',
    labelZhHant: '極低',
    labelEn: 'Minimal',
    labelFr: 'Minimal',
    labelDe: 'Minimal',
    labelJa: '最小',
  );
  static const _low = AiReasoningEffortOption(
    value: 'low',
    label: '低',
    labelZhHans: '低',
    labelZhHant: '低',
    labelEn: 'Low',
    labelFr: 'Faible',
    labelDe: 'Niedrig',
    labelJa: '低',
  );
  static const _medium = AiReasoningEffortOption(
    value: 'medium',
    label: '中',
    labelZhHans: '中',
    labelZhHant: '中',
    labelEn: 'Medium',
    labelFr: 'Moyen',
    labelDe: 'Mittel',
    labelJa: '中',
  );
  static const _high = AiReasoningEffortOption(
    value: 'high',
    label: '高',
    labelZhHans: '高',
    labelZhHant: '高',
    labelEn: 'High',
    labelFr: 'Élevé',
    labelDe: 'Hoch',
    labelJa: '高',
  );
  static const _xHigh = AiReasoningEffortOption(
    value: 'xhigh',
    label: '极高',
    labelZhHans: '极高',
    labelZhHant: '極高',
    labelEn: 'X-High',
    labelFr: 'Très élevé',
    labelDe: 'Sehr hoch',
    labelJa: '最高',
  );
  static const _max = AiReasoningEffortOption(
    value: 'max',
    label: '最高',
    labelZhHans: '最高',
    labelZhHant: '最高',
    labelEn: 'Max',
    labelFr: 'Maximum',
    labelDe: 'Maximal',
    labelJa: '最大',
  );

  static const lowMediumHigh = <AiReasoningEffortOption>[_low, _medium, _high];

  static const minimalLowMediumHigh = <AiReasoningEffortOption>[
    _minimal,
    ...lowMediumHigh,
  ];

  static const lowMediumHighMax = <AiReasoningEffortOption>[
    ...lowMediumHigh,
    _max,
  ];

  static const lowMediumHighXHighMax = <AiReasoningEffortOption>[
    ...lowMediumHigh,
    _xHigh,
    _max,
  ];

  static const openAiGpt5 = <AiReasoningEffortOption>[
    _none,
    ...minimalLowMediumHigh,
    _xHigh,
  ];

  static const openAiGpt56 = <AiReasoningEffortOption>[
    _none,
    ...lowMediumHighXHighMax,
  ];

  static const noneLowMediumHigh = <AiReasoningEffortOption>[
    _none,
    ...lowMediumHigh,
  ];

  static const thinkingBudgets = <AiReasoningEffortOption>[
    AiReasoningEffortOption(
      value: '1024',
      label: '轻量',
      labelZhHans: '轻量',
      labelZhHant: '輕量',
      labelEn: 'Light',
      labelFr: 'Léger',
      labelDe: 'Leicht',
      labelJa: '軽量',
    ),
    AiReasoningEffortOption(
      value: '8192',
      label: '均衡',
      labelZhHans: '均衡',
      labelZhHant: '均衡',
      labelEn: 'Balanced',
      labelFr: 'Équilibré',
      labelDe: 'Ausgewogen',
      labelJa: 'バランス',
    ),
    AiReasoningEffortOption(
      value: '32768',
      label: '深度',
      labelZhHans: '深度',
      labelZhHant: '深度',
      labelEn: 'Deep',
      labelFr: 'Approfondi',
      labelDe: 'Tief',
      labelJa: '深い',
    ),
  ];

  static List<AiReasoningEffortOption> standardValues(Iterable<String> values) {
    final supported = values.toSet();
    const options = <AiReasoningEffortOption>[
      _none,
      _minimal,
      _low,
      _medium,
      _high,
      _xHigh,
      _max,
    ];
    return List<AiReasoningEffortOption>.unmodifiable(
      options.where((option) => supported.contains(option.value)),
    );
  }

  final String value;
  final String label;
  final bool enabled;
  final String? labelZhHans;
  final String? labelZhHant;
  final String? labelEn;
  final String? labelFr;
  final String? labelDe;
  final String? labelJa;

  bool get isValid => nullIfBlank(value) != null;
  bool get isSelectable => enabled && isValid;

  String labelForLocaleName(String localeName) {
    final localeParts = localeName
        .replaceAll('_', '-')
        .split('-')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final languageCode = localeParts.isEmpty
        ? null
        : localeParts.first.toLowerCase();
    if (languageCode == 'zh') {
      final lower = localeName.toLowerCase();
      if (lower.contains('hant') ||
          lower.contains('tw') ||
          lower.contains('hk')) {
        return nullIfBlank(labelZhHant) ?? nullIfBlank(labelZhHans) ?? label;
      }
      return nullIfBlank(labelZhHans) ?? nullIfBlank(labelZhHant) ?? label;
    }
    return switch (languageCode) {
      'fr' => nullIfBlank(labelFr) ?? label,
      'de' => nullIfBlank(labelDe) ?? label,
      'ja' => nullIfBlank(labelJa) ?? label,
      _ => nullIfBlank(labelEn) ?? label,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'value': value,
      'label': label,
      if (!enabled) 'enabled': false,
      if (labelZhHans != null) 'label_zh_hans': labelZhHans,
      if (labelZhHant != null) 'label_zh_hant': labelZhHant,
      if (labelEn != null) 'label_en': labelEn,
      if (labelFr != null) 'label_fr': labelFr,
      if (labelDe != null) 'label_de': labelDe,
      if (labelJa != null) 'label_ja': labelJa,
    };
  }

  static String _readLabel(Map<String, Object?> json) {
    for (final key in const <String>[
      'label',
      'label_zh_hans',
      'label_en',
      'name',
      'display_name',
    ]) {
      final value = optionalStringFromValue(json[key]);
      if (value != null) return value;
    }
    return stringFromValue(json['value']).trim();
  }
}

class AiReasoningEffortPreset {
  const AiReasoningEffortPreset({
    required this.id,
    required this.label,
    required this.defaultValue,
    required this.options,
  });

  static const all = <AiReasoningEffortPreset>[
    AiReasoningEffortPreset(
      id: 'gemini',
      label: 'Gemini',
      defaultValue: 'medium',
      options: AiReasoningEffortOption.lowMediumHigh,
    ),
    AiReasoningEffortPreset(
      id: 'openai',
      label: 'OpenAI',
      defaultValue: 'medium',
      options: AiReasoningEffortOption.openAiGpt5,
    ),
    AiReasoningEffortPreset(
      id: 'anthropic',
      label: 'Anthropic',
      defaultValue: 'medium',
      options: AiReasoningEffortOption.lowMediumHighMax,
    ),
    AiReasoningEffortPreset(
      id: 'kimi',
      label: 'Kimi',
      defaultValue: 'medium',
      options: AiReasoningEffortOption.lowMediumHigh,
    ),
    AiReasoningEffortPreset(
      id: 'qwen',
      label: 'Qwen',
      defaultValue: '8192',
      options: AiReasoningEffortOption.thinkingBudgets,
    ),
    AiReasoningEffortPreset(
      id: 'glm',
      label: 'GLM',
      defaultValue: 'medium',
      options: AiReasoningEffortOption.lowMediumHigh,
    ),
    AiReasoningEffortPreset(
      id: 'seed',
      label: 'Seed',
      defaultValue: 'medium',
      options: AiReasoningEffortOption.lowMediumHigh,
    ),
    AiReasoningEffortPreset(
      id: 'grok',
      label: 'Grok',
      defaultValue: 'low',
      options: AiReasoningEffortOption.noneLowMediumHigh,
    ),
    AiReasoningEffortPreset(
      id: 'mistral',
      label: 'Mistral',
      defaultValue: 'medium',
      options: AiReasoningEffortOption.lowMediumHigh,
    ),
  ];

  final String id;
  final String label;
  final String defaultValue;
  final List<AiReasoningEffortOption> options;
}

// 枚举

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
    return enumByStorageValueOr(
      values,
      value,
      (scheme) => scheme.storageValue,
      fallback: AiAuthScheme.bearer,
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
  dots('dots'),
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
    return enumByStorageValueOr(
      values,
      value,
      (type) => type.storageValue,
      fallback: AiProtocolType.openai,
    );
  }

  String label(AppLocalizations l10n) {
    return switch (this) {
      AiProtocolType.openai => l10n.aiProtocolOpenAi,
      AiProtocolType.dots => l10n.aiProtocolDots,
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

// 模型配置档案

/// 模型支持的输入输出模态。
enum AiModelModality {
  text('text'),
  image('image'),
  video('video'),
  audio('audio'),
  file('file');

  const AiModelModality(this.storageValue);
  final String storageValue;

  static AiModelModality? fromStorage(String? value) {
    return enumByStorageValue(
      values,
      value,
      (modality) => modality.storageValue,
    );
  }
}

/// 模型支持的生成能力。
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
    return enumByStorageValue(
      values,
      value,
      (capability) => capability.storageValue,
    );
  }
}

/// 用户可配置的模型元数据；字段为 `null` 时使用目录或协议推断值。
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
    this.thinkingEnabled,
    this.reasoningEffortControlEnabled,
    this.reasoningEffort,
    this.reasoningEffortOptions = const <AiReasoningEffortOption>[],
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
      displayName: _readString(json['display_name']),
      description: _readString(json['description']),
      isMultimodal: _readBool(json['is_multimodal']),
      supportedModalities: _parseModalities(json['supported_modalities']),
      maxContextLength: _readNullablePositiveInt(json['max_context_length']),
      maxSummaryLength: _readNullablePositiveInt(json['max_summary_length']),
      maxOutputLength: _readNullablePositiveInt(json['max_output_length']),
      maxThinkingLength: _readNullablePositiveInt(json['max_thinking_length']),
      thinkingEnabled: _readBool(json[_thinkingEnabledJsonKey]),
      reasoningEffortControlEnabled: _readBool(
        json[_reasoningEffortControlEnabledJsonKey],
      ),
      reasoningEffort: optionalStringFromValue(json[_reasoningEffortJsonKey]),
      reasoningEffortOptions: _parseReasoningEffortOptions(
        json[_reasoningEffortOptionsJsonKey],
      ),
      requiresReasoningEcho: _readBool(json['requires_reasoning_echo']),
      capabilities: _parseCapabilities(json['capabilities']),
      supportsAttachments: _readBool(json['supports_attachments']),
      inputUsdPer1M: _readNullableNonNegativeDouble(json['input_usd_per_1m']),
      outputUsdPer1M: _readNullableNonNegativeDouble(json['output_usd_per_1m']),
      cacheReadUsdPer1M: _readNullableNonNegativeDouble(
        json['cache_read_usd_per_1m'],
      ),
      cacheWriteUsdPer1M: _readNullableNonNegativeDouble(
        json['cache_write_usd_per_1m'],
      ),
      canonicalSlug: _readString(json['canonical_slug']),
      huggingFaceId: _readString(json['hugging_face_id']),
      created: _readNullableInt(json['created']),
      architecture: json['architecture'] is Map
          ? AiModelArchitectureMetadata.fromJson(
              stringKeyedMapFromValue(json['architecture']),
            )
          : null,
      supportedParameters: _parseStringList(json['supported_parameters']),
      defaultParameters: _parseObjectMap(json['default_parameters']),
      supportedVoices: _parseStringList(json['supported_voices']),
      knowledgeCutoff: _readString(json['knowledge_cutoff']),
      expirationDate: _readString(json['expiration_date']),
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
      embeddingEndpointPath: _readString(json['embedding_endpoint_path']),
      embeddingBatchSize: _readNullablePositiveInt(
        json['embedding_batch_size'],
      ),
      embeddingRequiresSpecialBody:
          _readBool(json['embedding_requires_special_body']) ?? false,
      embeddingQueryModelId: _readString(json['embedding_query_model_id']),
      embeddingDocumentModelId: _readString(
        json['embedding_document_model_id'],
      ),
      embeddingInputTypes: _parseStringList(json['embedding_input_types']),
      embeddingDefaultInputType: _readString(
        json['embedding_default_input_type'],
      ),
      embeddingQueryInputType: _readString(json['embedding_query_input_type']),
      embeddingDocumentInputType: _readString(
        json['embedding_document_input_type'],
      ),
      embeddingSupportedTaskTypes: _parseStringList(
        json['embedding_supported_task_types'],
      ),
      embeddingDefaultTaskType: _readString(
        json['embedding_default_task_type'],
      ),
      embeddingDefaultQueryTaskType: _readString(
        json['embedding_default_query_task_type'],
      ),
      embeddingDefaultDocumentTaskType: _readString(
        json['embedding_default_document_task_type'],
      ),
      embeddingQueryTextPrefix: _readString(
        json['embedding_query_text_prefix'],
      ),
      embeddingDocumentTextPrefix: _readString(
        json['embedding_document_text_prefix'],
      ),
      embeddingEncodingFormats: _parseStringList(
        json['embedding_encoding_formats'],
      ),
      embeddingDefaultEncodingFormat: _readString(
        json['embedding_default_encoding_format'],
      ),
      embeddingOutputDTypes: _parseStringList(json['embedding_output_dtypes']),
      embeddingDefaultOutputDType: _readString(
        json['embedding_default_output_dtype'],
      ),
      embeddingDefaultTruncation: _readString(
        json['embedding_default_truncation'],
      ),
      embeddingSimilarityMetric: _readString(
        json['embedding_similarity_metric'],
      ),
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
      rerankEndpointPath: _readString(json['rerank_endpoint_path']),
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
      rerankDefaultInstruction: _readString(json['rerank_default_instruction']),
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
  static const String _thinkingEnabledJsonKey = 'thinking_enabled';
  static const String _reasoningEffortControlEnabledJsonKey =
      'reasoning_effort_control_enabled';
  static const String _reasoningEffortJsonKey = 'reasoning_effort';
  static const String _reasoningEffortOptionsJsonKey =
      'reasoning_effort_options';

  /// 面向用户的模型名称。
  final String? displayName;

  /// 模型简要说明。
  final String? description;

  /// 多模态开关；为 `null` 时自动推断。
  final bool? isMultimodal;

  /// 支持的模态；空集合表示使用默认值。
  final Set<AiModelModality> supportedModalities;

  /// Token 限制；为 `null` 时使用服务商或适配器默认值。
  final int? maxContextLength;
  final int? maxSummaryLength;
  final int? maxOutputLength;
  final int? maxThinkingLength;

  /// 是否启用思考模式；为 `null` 时根据目录和模型推断。
  final bool? thinkingEnabled;

  /// 是否发送推理强度；[reasoningEffort] 保留服务商原始值。
  final bool? reasoningEffortControlEnabled;
  final String? reasoningEffort;
  final List<AiReasoningEffortOption> reasoningEffortOptions;

  /// 后续请求是否必须回传历史 `reasoning_content`；为 `null` 时自动推断。
  final bool? requiresReasoningEcho;

  /// 支持的生成能力；空集合表示使用默认值。
  final Set<AiModelCapability> capabilities;

  /// 附件开关；为 `null` 时使用默认值。
  final bool? supportsAttachments;

  /// 成本控制：每百万 token 的价格（单位 USD）。
  /// `null` 表示未配置并跳过成本推算，应填写厂商官方价格。
  final double? inputUsdPer1M;
  final double? outputUsdPer1M;

  /// 缓存命中读取价（一般为输入价的 0.1–0.25）。
  final double? cacheReadUsdPer1M;

  /// 缓存创建写入价（一般为输入价的 1.25）。
  final double? cacheWriteUsdPer1M;

  /// 可用时原样保留 OpenRouter 字段。
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

  /// 是否作为应用级标题生成备用模型。
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

  /// 用户是否显式配置过此档案。
  bool get hasUserOverrides =>
      displayName != null ||
      description != null ||
      isMultimodal != null ||
      supportedModalities.isNotEmpty ||
      maxContextLength != null ||
      maxSummaryLength != null ||
      maxOutputLength != null ||
      maxThinkingLength != null ||
      thinkingEnabled != null ||
      reasoningEffortControlEnabled != null ||
      reasoningEffort != null ||
      reasoningEffortOptions.isNotEmpty ||
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
    bool? thinkingEnabled,
    bool clearThinkingEnabled = false,
    bool? reasoningEffortControlEnabled,
    bool clearReasoningEffortControlEnabled = false,
    String? reasoningEffort,
    bool clearReasoningEffort = false,
    List<AiReasoningEffortOption>? reasoningEffortOptions,
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
      thinkingEnabled: clearThinkingEnabled
          ? null
          : thinkingEnabled ?? this.thinkingEnabled,
      reasoningEffortControlEnabled: clearReasoningEffortControlEnabled
          ? null
          : reasoningEffortControlEnabled ?? this.reasoningEffortControlEnabled,
      reasoningEffort: clearReasoningEffort
          ? null
          : reasoningEffort ?? this.reasoningEffort,
      reasoningEffortOptions:
          reasoningEffortOptions ?? this.reasoningEffortOptions,
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
      if (thinkingEnabled != null) _thinkingEnabledJsonKey: thinkingEnabled,
      if (reasoningEffortControlEnabled != null)
        _reasoningEffortControlEnabledJsonKey: reasoningEffortControlEnabled,
      if (reasoningEffort != null) _reasoningEffortJsonKey: reasoningEffort,
      if (reasoningEffortOptions.isNotEmpty)
        _reasoningEffortOptionsJsonKey: reasoningEffortOptions
            .where((item) => item.isValid)
            .map((item) => item.toJson())
            .toList(growable: false),
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

  static List<AiReasoningEffortOption> _parseReasoningEffortOptions(
    Object? value,
  ) {
    if (value == null) return const <AiReasoningEffortOption>[];
    Object? raw = value;
    if (value is String) {
      final trimmed = nullIfBlank(value);
      if (trimmed == null) return const <AiReasoningEffortOption>[];
      try {
        raw = jsonDecode(trimmed);
      } catch (_) {
        return const <AiReasoningEffortOption>[];
      }
    }
    if (raw is! List) return const <AiReasoningEffortOption>[];
    final result = <AiReasoningEffortOption>[];
    final seen = <String>{};
    for (final item in raw) {
      final option = item is Map
          ? AiReasoningEffortOption.fromJson(stringKeyedMapFromValue(item))
          : AiReasoningEffortOption(
              value: stringFromValue(item).trim(),
              label: stringFromValue(item).trim(),
            );
      final normalizedValue = nullIfBlank(option.value);
      if (normalizedValue == null || !seen.add(normalizedValue)) continue;
      result.add(option);
    }
    return List<AiReasoningEffortOption>.unmodifiable(result);
  }

  static bool? _readBool(Object? value) {
    return optionalBoolFromValue(value);
  }

  static String? _readString(Object? value) {
    return value is String ? value : null;
  }
}

// 服务商配置

class AiModelConfig {
  factory AiModelConfig.fromJson(Map<String, Object?> json) {
    final availableModelIds = _parseAvailableModelIds(
      json['available_model_ids'],
    );
    final protocolType = AiProtocolType.fromStorage(
      stringFromValue(json['protocol_type']),
    );
    final rawApiDialect = nullIfBlank(stringFromValue(json['api_dialect']));
    final rawProviderKind = nullIfBlank(stringFromValue(json['provider_kind']));
    final apiDialect = rawApiDialect == null
        ? inferAiApiDialect(protocolType)
        : AiApiDialect.fromStorage(rawApiDialect);
    final providerKind = rawProviderKind == null
        ? inferAiProviderKind(protocolType)
        : AiProviderKind.fromStorage(rawProviderKind);
    return AiModelConfig(
      id: stringFromValue(json['id']),
      name: stringFromValue(json['name']),
      officialWebsiteUrl: _readOfficialWebsiteUrl(json),
      baseUrl: _normalizeBaseUrl(stringFromValue(json['base_url'])),
      autoCompleteBaseUrl: _readBool(json[_autoCompleteBaseUrlJsonKey]) ?? true,
      authScheme: AiAuthScheme.fromStorage(
        stringFromValue(json['auth_scheme']),
      ),
      token: '${json['token'] ?? ''}',
      modelId: stringFromValue(json['model_id']),
      protocolType: protocolType,
      apiDialect: apiDialect,
      providerKind: providerKind,
      explicitPromptCacheEnabled: _readExplicitPromptCacheEnabled(
        protocolType: protocolType,
        apiDialect: apiDialect,
        value: json[_explicitPromptCacheEnabledJsonKey],
      ),
      maxContextTokens: _readNullablePositiveInt(json['max_context_tokens']),
      availableModelIds: availableModelIds,
      defaultTitleModelId: stringFromValue(json['default_title_model_id']),
      isGlobalDefaultTitleModel:
          _readBool(json['is_global_default_title_model']) ?? false,
      customHeaders: _parseCustomHeaders(json['custom_headers']),
      requestMethod: _parseRequestMethod(json['request_method']),
      maxTokens: _readNullablePositiveInt(json['max_tokens']),
      temperature: _readNullableDouble(json['temperature']),
      streamEnabled: optionalBoolFromValue(json['stream_enabled']) ?? true,
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
           (protocolType == AiProtocolType.claude ||
               (apiDialect == AiApiDialect.anthropicNative &&
                   protocolType != AiProtocolType.dots)) &&
           (explicitPromptCacheEnabled ?? true);

  static final RegExp _reasoningModelIdSeparatorPattern = RegExp(r'[^a-z0-9]+');
  static final RegExp _reasoningModelIdRepeatedDashPattern = RegExp(r'-+');
  static final RegExp _reasoningModelIdEdgeDashPattern = RegExp(r'^-|-$');
  static final RegExp _officialWebsiteWhitespacePattern = RegExp(r'\s');
  static const Set<String> _thinkingParameterNames = <String>{
    'reasoning',
    'reasoning_effort',
    'include_reasoning',
    'enable_thinking',
    'thinking',
    'thinking_budget',
    'thinking_config',
    'thinkingconfig',
    'thinking_level',
    'thinkinglevel',
    'output_config',
  };
  static const Set<String> _deepSeekPlainChatModelIds = <String>{
    'deepseek-chat',
  };
  static const String _explicitPromptCacheEnabledJsonKey =
      'explicit_prompt_cache_enabled';
  static const String _autoCompleteBaseUrlJsonKey = 'auto_complete_base_url';
  static const String _officialWebsiteUrlJsonKey = 'official_website_url';

  static List<String> normalizeModelIds(Iterable<String> values) {
    final normalized = trimmedNonEmptyStrings(values).toSet();
    final sorted = normalized.toList()..sort();
    return sorted.toList(growable: false);
  }

  final String id;

  /// 服务商显示名称；为空时从 [baseUrl] 提取主机名。
  final String name;

  /// 设置页展示的服务商主页，仅接受 HTTP(S) 地址。
  final String officialWebsiteUrl;

  final String baseUrl;
  final bool autoCompleteBaseUrl;
  final AiAuthScheme authScheme;
  final String token;

  /// 当前启用的模型 ID。
  final String modelId;
  final AiProtocolType protocolType;
  final AiApiDialect apiDialect;
  final AiProviderKind providerKind;

  /// Claude 原生提示词缓存需同时通过服务商配置和全局成本控制开关启用。
  final bool explicitPromptCacheEnabled;

  final int? maxContextTokens;

  /// 自动扫描和手动添加的模型 ID。
  final List<String> availableModelIds;

  /// 仅用于会话标题生成的服务商级备用模型。
  final String defaultTitleModelId;

  /// 旧版服务商级标题模型标记，仅用于兼容历史设置。
  final bool isGlobalDefaultTitleModel;

  /// API 请求附带的自定义 HTTP 头。
  final Map<String, String> customHeaders;

  /// HTTP 请求方法，默认为 POST。
  final String requestMethod;

  /// 最大响应 Token 数；为 `null` 时使用适配器默认值。
  final int? maxTokens;

  /// 生成温度；为 `null` 时使用适配器默认值。
  final double? temperature;

  /// 是否使用 SSE 流式响应。
  final bool streamEnabled;

  /// 按模型 ID 存储的用户配置档案。
  final Map<String, AiModelProfile> modelProfiles;

  final Map<AiApiFamily, AiEndpointOverride> endpointOverrides;
  final AiOperationRouting operationRouting;
  final Map<AiApiFamily, String> capabilityOverrides;
  final Map<String, Object?> operationExtras;
  final AiRealtimeConfig realtime;

  /// 合并用户配置与内置目录，用户显式字段优先。
  AiModelProfile profileFor(String id) {
    final trimmedId = nullIfBlank(id) ?? '';
    AiModelProfile? override = _modelProfileOverrideFor(trimmedId);
    final catalog = AiModelCatalog.lookup(trimmedId, protocolType);
    if (override == null) {
      return _withReasoningEffortDefaults(
        catalog ?? const AiModelProfile(),
        modelId: trimmedId,
        protocolType: protocolType,
      );
    }
    if (catalog == null) {
      return _withReasoningEffortDefaults(
        override,
        modelId: trimmedId,
        protocolType: protocolType,
      );
    }
    return _withReasoningEffortDefaults(
      catalog.copyWith(
        displayName: override.displayName ?? catalog.displayName,
        description: override.description ?? catalog.description,
        isMultimodal: override.isMultimodal ?? catalog.isMultimodal,
        supportedModalities: override.supportedModalities.isNotEmpty
            ? override.supportedModalities
            : catalog.supportedModalities,
        maxContextLength: override.maxContextLength ?? catalog.maxContextLength,
        maxSummaryLength: override.maxSummaryLength ?? catalog.maxSummaryLength,
        maxOutputLength: override.maxOutputLength ?? catalog.maxOutputLength,
        maxThinkingLength:
            override.maxThinkingLength ?? catalog.maxThinkingLength,
        thinkingEnabled: override.thinkingEnabled ?? catalog.thinkingEnabled,
        reasoningEffortControlEnabled:
            override.reasoningEffortControlEnabled ??
            catalog.reasoningEffortControlEnabled,
        reasoningEffort: override.reasoningEffort ?? catalog.reasoningEffort,
        reasoningEffortOptions: override.reasoningEffortOptions.isNotEmpty
            ? override.reasoningEffortOptions
            : catalog.reasoningEffortOptions,
        requiresReasoningEcho:
            override.requiresReasoningEcho ?? catalog.requiresReasoningEcho,
        capabilities: override.capabilities.isNotEmpty
            ? override.capabilities
            : catalog.capabilities,
        supportsAttachments:
            override.supportsAttachments ?? catalog.supportsAttachments,
        inputUsdPer1M: override.inputUsdPer1M ?? catalog.inputUsdPer1M,
        outputUsdPer1M: override.outputUsdPer1M ?? catalog.outputUsdPer1M,
        cacheReadUsdPer1M:
            override.cacheReadUsdPer1M ?? catalog.cacheReadUsdPer1M,
        cacheWriteUsdPer1M:
            override.cacheWriteUsdPer1M ?? catalog.cacheWriteUsdPer1M,
        canonicalSlug: override.canonicalSlug ?? catalog.canonicalSlug,
        huggingFaceId: override.huggingFaceId ?? catalog.huggingFaceId,
        created: override.created ?? catalog.created,
        architecture: override.architecture ?? catalog.architecture,
        supportedParameters: override.supportedParameters.isNotEmpty
            ? override.supportedParameters
            : catalog.supportedParameters,
        defaultParameters: override.defaultParameters.isNotEmpty
            ? override.defaultParameters
            : catalog.defaultParameters,
        supportedVoices: override.supportedVoices.isNotEmpty
            ? override.supportedVoices
            : catalog.supportedVoices,
        knowledgeCutoff: override.knowledgeCutoff ?? catalog.knowledgeCutoff,
        expirationDate: override.expirationDate ?? catalog.expirationDate,
        links: override.links ?? catalog.links,
        isGlobalDefaultTitleModel:
            override.isGlobalDefaultTitleModel ||
            catalog.isGlobalDefaultTitleModel,
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
            override.embeddingDocumentModelId ??
            catalog.embeddingDocumentModelId,
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
            override.embeddingDefaultTaskType ??
            catalog.embeddingDefaultTaskType,
        embeddingDefaultQueryTaskType:
            override.embeddingDefaultQueryTaskType ??
            catalog.embeddingDefaultQueryTaskType,
        embeddingDefaultDocumentTaskType:
            override.embeddingDefaultDocumentTaskType ??
            catalog.embeddingDefaultDocumentTaskType,
        embeddingQueryTextPrefix:
            override.embeddingQueryTextPrefix ??
            catalog.embeddingQueryTextPrefix,
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
            override.rerankDefaultInstruction ??
            catalog.rerankDefaultInstruction,
        rerankSupportsTruncation:
            override.rerankSupportsTruncation ||
            catalog.rerankSupportsTruncation,
        rerankDefaultTruncation:
            override.rerankDefaultTruncation ?? catalog.rerankDefaultTruncation,
        readerSourceTypes: override.readerSourceTypes.isNotEmpty
            ? override.readerSourceTypes
            : catalog.readerSourceTypes,
        readerTargetTypes: override.readerTargetTypes.isNotEmpty
            ? override.readerTargetTypes
            : catalog.readerTargetTypes,
      ),
      modelId: trimmedId,
      protocolType: protocolType,
    );
  }

  AiModelProfile? _modelProfileOverrideFor(String modelId) {
    final normalizedId = modelId.toLowerCase();
    final baseId = AiOneMillionContextPolicy.stripModelIdSuffix(normalizedId);
    for (final entry in modelProfiles.entries) {
      final key = entry.key.toLowerCase();
      if (key == normalizedId) return entry.value;
    }
    if (baseId == normalizedId) return null;
    for (final entry in modelProfiles.entries) {
      if (entry.key.toLowerCase() == baseId) return entry.value;
    }
    return null;
  }

  static AiModelProfile _withReasoningEffortDefaults(
    AiModelProfile profile, {
    required String modelId,
    required AiProtocolType protocolType,
  }) {
    if (profile.reasoningEffortControlEnabled == false ||
        profile.reasoningEffortOptions.isNotEmpty) {
      return profile;
    }
    if (!supportsThinkingByDefault(
      modelId: modelId,
      protocolType: protocolType,
      profile: profile,
    )) {
      return profile;
    }
    final options = _defaultReasoningEffortOptions(
      modelId: modelId,
      protocolType: protocolType,
    );
    if (options.isEmpty) return profile;
    return profile.copyWith(
      reasoningEffortControlEnabled:
          profile.reasoningEffortControlEnabled ?? true,
      reasoningEffort:
          profile.reasoningEffort ??
          _defaultReasoningEffort(modelId: modelId, protocolType: protocolType),
      reasoningEffortOptions: options,
    );
  }

  static List<AiReasoningEffortOption> _defaultReasoningEffortOptions({
    required String modelId,
    required AiProtocolType protocolType,
  }) {
    final normalizedModelId = _normalizeReasoningModelId(modelId);
    if (normalizedModelId.contains('gpt-5-6')) {
      return AiReasoningEffortOption.openAiGpt56;
    }
    if (normalizedModelId.startsWith('gpt-5') ||
        normalizedModelId.contains('gpt-5')) {
      return AiReasoningEffortOption.openAiGpt5;
    }
    if (normalizedModelId.contains('grok-4-6')) {
      return AiReasoningEffortOption.standardValues(const <String>[
        'low',
        'medium',
        'high',
        'xhigh',
      ]);
    }
    if (normalizedModelId.contains('grok-4-5') ||
        normalizedModelId.contains('grok-build-latest')) {
      return AiReasoningEffortOption.standardValues(const <String>[
        'low',
        'medium',
        'high',
      ]);
    }
    if (protocolType == AiProtocolType.grok ||
        normalizedModelId.startsWith('grok')) {
      return AiReasoningEffortOption.noneLowMediumHigh;
    }
    if (protocolType == AiProtocolType.qwen ||
        normalizedModelId.startsWith('qwen') ||
        normalizedModelId.startsWith('qwq') ||
        normalizedModelId.startsWith('qvq')) {
      return AiReasoningEffortOption.thinkingBudgets;
    }
    if (protocolType == AiProtocolType.gemini ||
        normalizedModelId.startsWith('gemini')) {
      return AiReasoningEffortOption.lowMediumHigh;
    }
    if (protocolType == AiProtocolType.claude ||
        normalizedModelId.contains('claude')) {
      return _looksLikeClaudeXHighEffortModel(normalizedModelId)
          ? AiReasoningEffortOption.lowMediumHighXHighMax
          : _looksLikeClaudeOutputEffortModel(normalizedModelId)
          ? AiReasoningEffortOption.lowMediumHighMax
          : AiReasoningEffortOption.lowMediumHigh;
    }
    if (protocolType == AiProtocolType.deepseek ||
        normalizedModelId.startsWith('deepseek') ||
        protocolType == AiProtocolType.glm ||
        protocolType == AiProtocolType.minimax ||
        protocolType == AiProtocolType.stepfun ||
        protocolType == AiProtocolType.mimo ||
        normalizedModelId.startsWith('o1') ||
        normalizedModelId.startsWith('o3') ||
        normalizedModelId.startsWith('o4') ||
        normalizedModelId.contains('-o1') ||
        normalizedModelId.contains('-o3') ||
        normalizedModelId.contains('-o4') ||
        normalizedModelId.contains('magistral') ||
        normalizedModelId.contains('mistral-reasoning') ||
        normalizedModelId.contains('spark-x') ||
        ((normalizedModelId.contains('spark') ||
                normalizedModelId.contains('xinghuo') ||
                normalizedModelId.contains('xunfei') ||
                normalizedModelId.contains('xfyun')) &&
            (normalizedModelId.contains('x1') ||
                normalizedModelId.contains('x2')))) {
      return AiReasoningEffortOption.lowMediumHigh;
    }
    return const <AiReasoningEffortOption>[];
  }

  static String _defaultReasoningEffort({
    required String modelId,
    required AiProtocolType protocolType,
  }) {
    final normalizedModelId = _normalizeReasoningModelId(modelId);
    if (normalizedModelId.contains('grok-4-5') ||
        normalizedModelId.contains('grok-build-latest')) {
      return 'high';
    }
    if (protocolType == AiProtocolType.qwen ||
        normalizedModelId.startsWith('qwen') ||
        normalizedModelId.startsWith('qwq') ||
        normalizedModelId.startsWith('qvq')) {
      return '8192';
    }
    if (protocolType == AiProtocolType.grok ||
        normalizedModelId.startsWith('grok')) {
      return 'low';
    }
    return 'medium';
  }

  static bool _looksLikeClaudeOutputEffortModel(String normalizedModelId) {
    return normalizedModelId.contains('opus-5') ||
        normalizedModelId.contains('5-opus') ||
        normalizedModelId.contains('sonnet-5') ||
        normalizedModelId.contains('5-sonnet') ||
        normalizedModelId.contains('fable-5') ||
        normalizedModelId.contains('5-fable') ||
        normalizedModelId.contains('mythos-5') ||
        normalizedModelId.contains('5-mythos') ||
        normalizedModelId.contains('haiku-5') ||
        normalizedModelId.contains('5-haiku') ||
        normalizedModelId.contains('mythos-preview') ||
        normalizedModelId.contains('opus-4-8') ||
        normalizedModelId.contains('4-8-opus') ||
        normalizedModelId.contains('opus-4-7') ||
        normalizedModelId.contains('4-7-opus') ||
        normalizedModelId.contains('opus-4-6') ||
        normalizedModelId.contains('4-6-opus') ||
        normalizedModelId.contains('opus-4-5') ||
        normalizedModelId.contains('4-5-opus') ||
        normalizedModelId.contains('sonnet-4-6') ||
        normalizedModelId.contains('4-6-sonnet');
  }

  static bool _looksLikeClaudeXHighEffortModel(String normalizedModelId) {
    return normalizedModelId.contains('opus-5') ||
        normalizedModelId.contains('5-opus') ||
        normalizedModelId.contains('sonnet-5') ||
        normalizedModelId.contains('5-sonnet') ||
        normalizedModelId.contains('fable-5') ||
        normalizedModelId.contains('5-fable') ||
        normalizedModelId.contains('mythos-5') ||
        normalizedModelId.contains('5-mythos') ||
        normalizedModelId.contains('haiku-5') ||
        normalizedModelId.contains('5-haiku') ||
        normalizedModelId.contains('mythos-preview') ||
        normalizedModelId.contains('opus-4-8') ||
        normalizedModelId.contains('4-8-opus') ||
        normalizedModelId.contains('opus-4-7') ||
        normalizedModelId.contains('4-7-opus');
  }

  /// 是否允许附件；用户未显式配置时默认允许，由协议适配器校验具体类型。
  bool get resolvedSupportsAttachments =>
      profileFor(modelId).supportsAttachments ?? true;

  bool get supportsExplicitPromptCacheControl =>
      protocolType == AiProtocolType.claude ||
      (apiDialect == AiApiDialect.anthropicNative &&
          protocolType != AiProtocolType.dots);

  bool get effectiveExplicitPromptCacheEnabled =>
      supportsExplicitPromptCacheControl && explicitPromptCacheEnabled;

  bool get resolvedSupportsThinking {
    final trimmedModelId = nullIfBlank(modelId) ?? '';
    final profile = profileFor(trimmedModelId);
    final catalogProfile = AiModelCatalog.lookup(trimmedModelId, protocolType);
    return supportsThinkingByDefault(
          modelId: trimmedModelId,
          protocolType: protocolType,
          profile: profile,
        ) ||
        (catalogProfile != null &&
            supportsThinkingByDefault(
              modelId: trimmedModelId,
              protocolType: protocolType,
              profile: catalogProfile,
            )) ||
        modelProfiles[trimmedModelId]?.thinkingEnabled == true;
  }

  bool get resolvedThinkingEnabled {
    final trimmedModelId = nullIfBlank(modelId) ?? '';
    final normalizedModelId = _normalizeReasoningModelId(trimmedModelId);
    if (_looksLikeAlwaysOnClaudeAdaptiveThinking(normalizedModelId) ||
        _looksLikeAlwaysOnGrokReasoning(normalizedModelId) ||
        _looksLikeAlwaysOnGemini37(normalizedModelId) ||
        _looksLikeAlwaysOnKimiK3(normalizedModelId) ||
        _looksLikeAlwaysOnGlm53(normalizedModelId)) {
      return true;
    }
    final userOverride = modelProfiles[trimmedModelId]?.thinkingEnabled;
    if (userOverride != null) {
      return userOverride;
    }
    final profile = profileFor(trimmedModelId);
    return thinkingEnabledByDefault(
      modelId: trimmedModelId,
      protocolType: protocolType,
      profile: profile,
    );
  }

  List<AiReasoningEffortOption> get resolvedReasoningEffortOptions {
    return profileFor(modelId).reasoningEffortOptions;
  }

  bool get resolvedReasoningEffortControlEnabled {
    if (protocolType == AiProtocolType.dots &&
        apiDialect != AiApiDialect.anthropicNative) {
      return false;
    }
    final trimmedModelId = nullIfBlank(modelId) ?? '';
    final normalizedModelId = _normalizeReasoningModelId(trimmedModelId);
    if (!resolvedThinkingEnabled &&
        !_looksLikeClaudeOutputEffortModel(normalizedModelId)) {
      return false;
    }
    final userOverride =
        modelProfiles[trimmedModelId]?.reasoningEffortControlEnabled;
    if (userOverride != null) return userOverride;
    return profileFor(trimmedModelId).reasoningEffortControlEnabled ?? false;
  }

  static bool _looksLikeAlwaysOnClaudeAdaptiveThinking(
    String normalizedModelId,
  ) {
    return normalizedModelId.contains('fable-5') ||
        normalizedModelId.contains('5-fable') ||
        normalizedModelId.contains('mythos-5') ||
        normalizedModelId.contains('5-mythos') ||
        normalizedModelId.contains('mythos-preview');
  }

  static bool _looksLikeAlwaysOnGrokReasoning(String normalizedModelId) {
    return normalizedModelId.contains('grok-4-6') ||
        normalizedModelId.contains('grok-4-5') ||
        normalizedModelId.contains('grok-build-latest');
  }

  static bool _looksLikeAlwaysOnGemini37(String normalizedModelId) {
    return normalizedModelId.contains('gemini-3-7-flash');
  }

  static bool _looksLikeAlwaysOnKimiK3(String normalizedModelId) {
    return normalizedModelId.contains('kimi-k3') || normalizedModelId == 'k3';
  }

  static bool _looksLikeAlwaysOnGlm53(String normalizedModelId) {
    return normalizedModelId.contains('glm-5-3');
  }

  String? get resolvedReasoningEffort {
    if (!resolvedReasoningEffortControlEnabled) return null;
    final profile = profileFor(modelId);
    final configured = nullIfBlank(profile.reasoningEffort);
    AiReasoningEffortOption? configuredOption;
    if (configured != null) {
      for (final option in profile.reasoningEffortOptions) {
        if (option.value == configured) {
          configuredOption = option;
          break;
        }
      }
    }
    if (configured != null &&
        (configuredOption == null || configuredOption.isSelectable)) {
      return configured;
    }
    for (final option in profile.reasoningEffortOptions) {
      if (option.isSelectable) return option.value;
    }
    return null;
  }

  String? reasoningEffortLabelForLocaleName(String localeName) {
    final effort = resolvedReasoningEffort;
    if (effort == null) return null;
    for (final option in resolvedReasoningEffortOptions) {
      if (option.value == effort) {
        return option.labelForLocaleName(localeName);
      }
    }
    return effort;
  }

  static bool thinkingEnabledByDefault({
    required String modelId,
    required AiProtocolType protocolType,
    required AiModelProfile profile,
  }) {
    final explicit = profile.thinkingEnabled;
    if (explicit != null) return explicit;
    if (_defaultParametersDisableThinking(profile.defaultParameters)) {
      return false;
    }
    if ((profile.maxThinkingLength ?? 0) > 0) return true;
    if (_defaultParametersEnableThinking(profile.defaultParameters)) {
      return true;
    }
    final normalizedModelId = _normalizeReasoningModelId(modelId);
    if (_looksLikeThinkingCapableModel(normalizedModelId, protocolType)) {
      return true;
    }
    return _profileHasThinkingParameter(profile);
  }

  static bool supportsThinkingByDefault({
    required String modelId,
    required AiProtocolType protocolType,
    required AiModelProfile profile,
  }) {
    if (profile.thinkingEnabled != null) return true;
    if ((profile.maxThinkingLength ?? 0) > 0) return true;
    if (_profileHasThinkingParameter(profile)) return true;
    final normalizedModelId = _normalizeReasoningModelId(modelId);
    return _looksLikeThinkingCapableModel(normalizedModelId, protocolType);
  }

  bool get requiresReasoningEcho {
    final trimmedModelId = nullIfBlank(modelId) ?? '';
    final normalizedModelId = _normalizeReasoningModelId(trimmedModelId);
    if (_looksLikeAlwaysOnKimiK3(normalizedModelId)) {
      return true;
    }
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
    // xAI 多轮缓存要求推理模型原样接收历史 `reasoning_content`。
    if (_looksLikeGrokReasoningModel(normalizedModelId)) {
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
    return lowercaseStringFromValue(value).contains('deepseek');
  }

  static String _normalizeReasoningModelId(String value) {
    return lowercaseStringFromValue(value)
        .replaceAll(_reasoningModelIdSeparatorPattern, '-')
        .replaceAll(_reasoningModelIdRepeatedDashPattern, '-')
        .replaceAll(_reasoningModelIdEdgeDashPattern, '');
  }

  static bool _profileHasThinkingParameter(AiModelProfile profile) {
    return profile.supportedParameters.any(_isThinkingParameterName) ||
        _mapHasThinkingParameter(profile.defaultParameters);
  }

  static bool _isThinkingParameterName(String value) {
    final normalized = lowercaseStringFromValue(
      value,
    ).replaceAll('-', '_').replaceAll('.', '_');
    return _thinkingParameterNames.contains(normalized);
  }

  static bool _mapHasThinkingParameter(Map<String, Object?> map) {
    if (map.isEmpty) return false;
    for (final entry in map.entries) {
      if (_isThinkingParameterName(entry.key)) return true;
      final value = entry.value;
      if (value is Map &&
          _mapHasThinkingParameter(stringKeyedMapFromValue(value))) {
        return true;
      }
    }
    return false;
  }

  static bool _defaultParametersEnableThinking(Map<String, Object?> map) {
    if (map.isEmpty) return false;
    for (final entry in map.entries) {
      final value = entry.value;
      if (_isThinkingParameterName(entry.key) && value == true) {
        return true;
      }
      if (entry.key == 'reasoning' && value is Map) {
        final reasoning = stringKeyedMapFromValue(value);
        if (_readBool(reasoning['enabled']) == true) return true;
        if (_readBool(reasoning['exclude']) == false) return true;
      }
      if (entry.key == 'thinking' && value is Map) {
        final thinking = stringKeyedMapFromValue(value);
        final type = lowercaseStringFromValue(thinking['type']);
        if (type == 'enabled' || type == 'adaptive') return true;
      }
      if (value is Map &&
          _defaultParametersEnableThinking(stringKeyedMapFromValue(value))) {
        return true;
      }
    }
    return false;
  }

  static bool _defaultParametersDisableThinking(Map<String, Object?> map) {
    if (map.isEmpty) return false;
    for (final entry in map.entries) {
      final value = entry.value;
      if (_isThinkingParameterName(entry.key) && value == false) {
        return true;
      }
      if (entry.key == 'reasoning' && value is Map) {
        final reasoning = stringKeyedMapFromValue(value);
        if (_readBool(reasoning['enabled']) == false) return true;
        if (_readBool(reasoning['exclude']) == true) return true;
      }
      if (entry.key == 'thinking' && value is Map) {
        final thinking = stringKeyedMapFromValue(value);
        if (lowercaseStringFromValue(thinking['type']) == 'disabled') {
          return true;
        }
      }
      if (value is Map &&
          _defaultParametersDisableThinking(stringKeyedMapFromValue(value))) {
        return true;
      }
    }
    return false;
  }

  static bool _looksLikeThinkingCapableModel(
    String normalizedModelId,
    AiProtocolType protocolType,
  ) {
    if (normalizedModelId.isEmpty) return false;
    if (normalizedModelId.contains('thinking') ||
        normalizedModelId.contains('think') ||
        normalizedModelId.contains('reasoner') ||
        normalizedModelId.contains('reasoning') ||
        normalizedModelId.contains('deep-research')) {
      return true;
    }
    if (_looksLikeDeepSeekReasoningModel(normalizedModelId) ||
        _looksLikeDeepSeekHybridThinkingModel(normalizedModelId)) {
      return true;
    }
    return switch (protocolType) {
      AiProtocolType.openai =>
        normalizedModelId.startsWith('o1') ||
            normalizedModelId.startsWith('o3') ||
            normalizedModelId.startsWith('o4') ||
            normalizedModelId.startsWith('gpt-5'),
      AiProtocolType.dots => normalizedModelId.startsWith('dots'),
      AiProtocolType.claude =>
        normalizedModelId.contains('sonnet-5') ||
            normalizedModelId.contains('5-sonnet') ||
            normalizedModelId.contains('opus-5') ||
            normalizedModelId.contains('5-opus') ||
            normalizedModelId.contains('haiku-5') ||
            normalizedModelId.contains('5-haiku') ||
            normalizedModelId.contains('fable-5') ||
            normalizedModelId.contains('5-fable') ||
            normalizedModelId.contains('mythos-5') ||
            normalizedModelId.contains('5-mythos') ||
            normalizedModelId.contains('claude-4') ||
            normalizedModelId.contains('sonnet-4') ||
            normalizedModelId.contains('opus-4') ||
            normalizedModelId.contains('haiku-4') ||
            normalizedModelId.contains('claude-sonnet') ||
            normalizedModelId.contains('claude-opus'),
      AiProtocolType.gemini => normalizedModelId.contains('gemini-2-5'),
      AiProtocolType.deepseek =>
        _looksLikeDeepSeekReasoningModel(normalizedModelId) ||
            _looksLikeDeepSeekHybridThinkingModel(normalizedModelId),
      AiProtocolType.qwen =>
        normalizedModelId.contains('qwen3') ||
            normalizedModelId.contains('qwq') ||
            normalizedModelId.contains('qvq'),
      AiProtocolType.glm =>
        normalizedModelId.contains('glm-4-5') ||
            normalizedModelId.contains('glm-4-6') ||
            normalizedModelId.contains('glm-z1'),
      AiProtocolType.grok =>
        normalizedModelId.contains('grok-3-mini') ||
            normalizedModelId.contains('grok-4'),
      AiProtocolType.seed =>
        normalizedModelId.contains('seed-1-6') ||
            normalizedModelId.contains('doubao-seed'),
      AiProtocolType.stepfun => normalizedModelId.contains('step-3'),
      AiProtocolType.minimax =>
        normalizedModelId.contains('m1') ||
            normalizedModelId.contains('m2') ||
            normalizedModelId.contains('m2-1'),
      AiProtocolType.kimi =>
        normalizedModelId.contains('k1') ||
            normalizedModelId.contains('k2') ||
            normalizedModelId.contains('kimi-k'),
      AiProtocolType.hunyuan => normalizedModelId.contains('t1'),
      AiProtocolType.wenxin => normalizedModelId.contains('ernie-x1'),
      AiProtocolType.longcat => normalizedModelId.contains('longcat'),
      AiProtocolType.vllm || AiProtocolType.sglang =>
        normalizedModelId.contains('r1') ||
            normalizedModelId.contains('qwq') ||
            normalizedModelId.contains('qwen3') ||
            normalizedModelId.contains('glm-z1'),
      AiProtocolType.ollama ||
      AiProtocolType.agnes ||
      AiProtocolType.joycode ||
      AiProtocolType.meta ||
      AiProtocolType.mimo => false,
    };
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

  static bool _looksLikeGrokReasoningModel(String normalizedModelId) {
    return normalizedModelId.startsWith('grok-3-mini') ||
        normalizedModelId.contains('-grok-3-mini') ||
        normalizedModelId.startsWith('grok-4') ||
        normalizedModelId.contains('-grok-4') ||
        normalizedModelId.contains('grok-build-latest');
  }

  String get normalizedBaseUrl => _normalizeBaseUrl(baseUrl);

  Uri? get officialWebsiteUri => _parseOfficialWebsiteUri(officialWebsiteUrl);

  String get normalizedOfficialWebsiteUrl =>
      officialWebsiteUri?.toString() ?? '';

  String resolveOperationModelId(AiApiFamily family) {
    return operationRouting.resolveModelId(family, modelId) ??
        (nullIfBlank(modelId) ?? '');
  }

  String? capabilityStatusFor(AiApiFamily family) {
    return nullIfBlank(capabilityOverrides[family]);
  }

  /// 服务商短名称：依次使用自定义名称、主机名和协议类型。
  String get providerLabel {
    final trimmedName = nullIfBlank(name);
    if (trimmedName != null) return trimmedName;
    final host = nullIfBlank(Uri.tryParse(normalizedBaseUrl)?.host);
    return host ?? protocolType.storageValue.toUpperCase();
  }

  String get displayName {
    return nullIfBlank(modelId) ?? protocolType.storageValue.toUpperCase();
  }

  String get maskedToken {
    final trimmedToken = nullIfBlank(token);
    if (trimmedToken == null) {
      return '';
    }
    if (trimmedToken.length <= 8) {
      return '*' * trimmedToken.length;
    }
    final visibleSuffix = trimmedToken.substring(trimmedToken.length - 4);
    return '${'*' * (trimmedToken.length - 4)}$visibleSuffix';
  }

  /// 返回合并当前模型与可用模型后的去重有序列表。
  List<String> get allModelIds {
    final normalizedModelId = nullIfBlank(modelId);
    final normalizedTitleModelId = nullIfBlank(defaultTitleModelId);
    return normalizeModelIds(<String>[
      ...availableModelIds,
      if (normalizedModelId != null) normalizedModelId,
      if (normalizedTitleModelId != null) normalizedTitleModelId,
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
      final value = nullIfBlank(entry.value);
      if (value != null) {
        capabilityOverridesJson[entry.key.storageValue] = value;
      }
    }
    final normalizedDefaultTitleModelId = nullIfBlank(defaultTitleModelId);
    return <String, Object?>{
      'id': id,
      'name': name,
      if (normalizedOfficialWebsiteUrl.isNotEmpty)
        _officialWebsiteUrlJsonKey: normalizedOfficialWebsiteUrl,
      'base_url': normalizedBaseUrl,
      _autoCompleteBaseUrlJsonKey: autoCompleteBaseUrl,
      'auth_scheme': authScheme.storageValue,
      'token': token,
      'model_id': nullIfBlank(modelId) ?? '',
      'protocol_type': protocolType.storageValue,
      'api_dialect': apiDialect.storageValue,
      'provider_kind': providerKind.storageValue,
      if (supportsExplicitPromptCacheControl)
        _explicitPromptCacheEnabledJsonKey: effectiveExplicitPromptCacheEnabled,
      'max_context_tokens': maxContextTokens,
      'available_model_ids': normalizeModelIds(availableModelIds),
      if (normalizedDefaultTitleModelId != null)
        'default_title_model_id': normalizedDefaultTitleModelId,
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
    final trimmedValue = nullIfBlank(value);
    if (trimmedValue == null) return '';
    return trimmedValue.endsWith('/')
        ? trimmedValue.substring(0, trimmedValue.length - 1)
        : trimmedValue;
  }

  static Uri? _parseOfficialWebsiteUri(String value) {
    final trimmedValue = nullIfBlank(value);
    if (trimmedValue == null ||
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
    if (nullIfBlank(uri.host) == null || nullIfBlank(uri.userInfo) != null) {
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
      final normalized = _normalizeOfficialWebsiteUrl(
        stringFromValue(json[key]),
      );
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
    required AiApiDialect apiDialect,
    required Object? value,
  }) {
    final supported =
        protocolType == AiProtocolType.claude ||
        (apiDialect == AiApiDialect.anthropicNative &&
            protocolType != AiProtocolType.dots);
    if (!supported) {
      return false;
    }
    return value is! bool || value;
  }

  /// 解析列表或 TOML 中二次 JSON 编码的 `available_model_ids`。
  static List<String> _parseAvailableModelIds(Object? value) {
    if (value == null) {
      return const <String>[];
    }
    if (value is List) {
      return normalizeModelIds(trimmedNonEmptyStrings(value));
    }
    if (value is String) {
      final trimmed = nullIfBlank(value);
      if (trimmed == null) return const <String>[];
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return normalizeModelIds(trimmedNonEmptyStrings(decoded));
        }
      } catch (_) {
        // 无效 JSON，忽略。
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
        final key = optionalStringFromValue(entry.key);
        if (key == null) continue;
        result[key] = stringFromValue(entry.value);
      }
      return result;
    }
    if (value is String) {
      final trimmed = nullIfBlank(value);
      if (trimmed == null) return const <String, String>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return _parseCustomHeaders(decoded);
        }
      } catch (_) {
        // 无效 JSON，忽略。
      }
    }
    return const <String, String>{};
  }

  static double? _readNullableDouble(Object? value) {
    return optionalDoubleFromValue(value);
  }

  static String _parseRequestMethod(Object? value) {
    final raw = stringFromValue(value).toUpperCase();
    if (raw.isEmpty) return 'POST';
    return raw;
  }

  static Map<String, AiModelProfile> _parseModelProfiles(Object? value) {
    if (value == null) return const <String, AiModelProfile>{};
    Map<String, Object?>? map;
    if (value is Map) {
      map = stringKeyedMapFromValue(value);
    } else if (value is String) {
      final trimmed = nullIfBlank(value);
      if (trimmed == null) return const <String, AiModelProfile>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          map = stringKeyedMapFromValue(decoded);
        }
      } catch (_) {
        // 无效 JSON，忽略。
      }
    }
    if (map == null) return const <String, AiModelProfile>{};
    final result = <String, AiModelProfile>{};
    for (final entry in map.entries) {
      final key = nullIfBlank(entry.key);
      if (key == null) continue;
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
      final family = AiApiFamily.fromStorage(stringFromValue(entry.key));
      final status = optionalStringFromValue(entry.value);
      if (family == null || status == null) continue;
      result[family] = status;
    }
    return result;
  }

  static Map<String, Object?> _parseOperationExtras(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.of(stringKeyedMapFromValue(value));
    }
    if (value is String) {
      final trimmed = nullIfBlank(value);
      if (trimmed == null) return const <String, Object?>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return Map<String, Object?>.of(stringKeyedMapFromValue(decoded));
        }
      } catch (_) {
        // 无效 JSON，忽略。
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
    AiProtocolType.dots => AiProviderKind.custom,
    AiProtocolType.claude => AiProviderKind.claude,
    AiProtocolType.gemini => AiProviderKind.gemini,
    AiProtocolType.qwen => AiProviderKind.qwen,
    AiProtocolType.minimax => AiProviderKind.minimax,
    _ => AiProviderKind.custom,
  };
}
