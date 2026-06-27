import 'ai_model_config.dart';
import 'openrouter_exact_model_catalog.dart';

/// Hardcoded catalog of mainstream AI model specifications.
///
/// Provides sensible pre-fill defaults for [AiModelProfile] when users
/// configure a model profile for the first time.  Entries are organized by
/// [AiProtocolType] and matched against model-ID patterns (case-insensitive,
/// most-specific first).
///
/// ## Maintenance
///
/// * Find the provider section (e.g. `_openai`, `_claude`).
/// * Insert/update entries – keep **more specific patterns above** less
///   specific ones so that `gpt-4o-mini` matches before `gpt-4o`.
/// * Use the [_p] helper to construct entries concisely.
class AiModelCatalog {
  AiModelCatalog._();

  // ═══════════════════════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns a pre-filled [AiModelProfile] for [modelId] under the given
  /// [protocolType], or `null` if no catalog entry matches.
  static AiModelProfile? lookup(String modelId, AiProtocolType protocolType) {
    final id = modelId.toLowerCase().trim();
    if (id.isEmpty) return null;

    final exact = _exactModelProfiles[id];
    if (exact != null) {
      return exact;
    }

    // Protocol-specific lookup.
    final result = switch (protocolType) {
      AiProtocolType.openai => _openai(id),
      AiProtocolType.claude => _claude(id),
      AiProtocolType.gemini => _gemini(id),
      AiProtocolType.deepseek => _deepseek(id),
      AiProtocolType.qwen => _qwen(id),
      AiProtocolType.glm => _glm(id),
      AiProtocolType.kimi => _kimi(id),
      AiProtocolType.seed => _seed(id),
      AiProtocolType.stepfun => _stepfun(id),
      AiProtocolType.minimax => _minimax(id),
      AiProtocolType.longcat => _longcat(id),
      AiProtocolType.agnes => _agnes(id),
      AiProtocolType.joycode => _joycode(id),
      AiProtocolType.wenxin => _wenxin(id),
      AiProtocolType.meta => _meta(id),
      AiProtocolType.grok => _grok(id),
      AiProtocolType.hunyuan => _hunyuan(id),
      AiProtocolType.mimo => _mimo(id),
      // Local inference frameworks serve arbitrary open-source models.
      AiProtocolType.ollama ||
      AiProtocolType.vllm ||
      AiProtocolType.sglang => null,
    };
    if (result != null) return result;

    // Cross-protocol fallback: try all providers for well-known model-ID
    // patterns.  Handles cases like DeepSeek models served via Aliyun/Qwen,
    // or GLM models accessed through OpenAI-compatible endpoints.
    return _openai(id) ??
        _gemini(id) ??
        _mistral(id) ??
        _cohere(id) ??
        _voyage(id) ??
        _jina(id) ??
        _openSourceEmbedding(id) ??
        _claude(id) ??
        _deepseek(id) ??
        _qwen(id) ??
        _glm(id) ??
        _kimi(id) ??
        _stepfun(id) ??
        _seed(id) ??
        _minimax(id) ??
        _agnes(id) ??
        _longcat(id) ??
        _joycode(id) ??
        _wenxin(id) ??
        _meta(id) ??
        _grok(id) ??
        _hunyuan(id);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers & common modality / capability constants
  // ═══════════════════════════════════════════════════════════════════════════

  static const _textImage = <AiModelModality>{
    AiModelModality.text,
    AiModelModality.image,
  };

  static const _textImageVideo = <AiModelModality>{
    AiModelModality.text,
    AiModelModality.image,
    AiModelModality.video,
  };

  static const _allModalities = <AiModelModality>{
    AiModelModality.text,
    AiModelModality.image,
    AiModelModality.video,
    AiModelModality.audio,
  };

  static const _imageGen = <AiModelCapability>{
    AiModelCapability.imageGeneration,
  };

  static const _videoGen = <AiModelCapability>{
    AiModelCapability.videoGeneration,
  };

  static const _audioGen = <AiModelCapability>{
    AiModelCapability.audioGeneration,
  };

  static const _embeddingGen = <AiModelCapability>{
    AiModelCapability.embeddingGeneration,
  };

  static const _openAiEmbeddingParameters = <String>[
    'input',
    'model',
    'dimensions',
    'encoding_format',
    'user',
  ];

  static const _openAiLegacyEmbeddingParameters = <String>[
    'input',
    'model',
    'encoding_format',
    'user',
  ];

  static const _openAiCompatibleEmbeddingParameters = <String>[
    'input',
    'model',
  ];

  static const _typedOpenAiCompatibleEmbeddingParameters = <String>[
    'input',
    'model',
    'input_type',
    'truncate',
  ];

  static const _perplexityEmbeddingParameters = <String>[
    'input',
    'model',
    'dimensions',
    'encoding_format',
  ];

  static const _qwenTextEmbeddingParameters = <String>[
    'input',
    'model',
    'dimensions',
  ];

  static const _qwenMultimodalEmbeddingParameters = <String>[
    'input',
    'parameters.enable_fusion',
    'parameters.dimension',
  ];

  static const _geminiEmbeddingParameters = <String>[
    'content',
    'taskType',
    'title',
    'outputDimensionality',
  ];

  static const _geminiMultimodalEmbeddingParameters = <String>[
    'content',
    'outputDimensionality',
  ];

  static const _geminiLegacyEmbeddingParameters = <String>[
    'content',
    'taskType',
    'title',
  ];

  static const _mistralEmbeddingParameters = <String>[
    'input',
    'model',
    'output_dimension',
    'output_dtype',
  ];

  static const _cohereEmbeddingParameters = <String>[
    'texts',
    'model',
    'input_type',
    'embedding_types',
    'truncate',
  ];

  static const _voyageEmbeddingParameters = <String>[
    'input',
    'model',
    'input_type',
    'truncation',
    'output_dimension',
    'output_dtype',
  ];

  static const _jinaEmbeddingParameters = <String>[
    'input',
    'model',
    'task',
    'dimensions',
    'embedding_type',
    'normalized',
  ];

  static final Map<String, AiModelProfile> _exactModelProfiles =
      openRouterExactModelProfiles;

  /// Shorthand [AiModelProfile] builder for catalog entries.
  static AiModelProfile _p({
    required String name,
    String? desc,
    bool multimodal = false,
    bool? supportsAttachments,
    bool? requiresReasoningEcho,
    Set<AiModelModality> modalities = const <AiModelModality>{
      AiModelModality.text,
    },
    int? context,
    int? summary,
    int? output,
    int? thinking,
    double? inputUsdPer1M,
    double? outputUsdPer1M,
    double? cacheReadUsdPer1M,
    double? cacheWriteUsdPer1M,
    List<String> supportedParameters = const <String>[],
    Map<String, Object?> defaultParameters = const <String, Object?>{},
    Set<AiModelCapability> capabilities = const <AiModelCapability>{},
    int? embeddingDimensions,
    int? embeddingMaxInputTokens,
    bool embeddingSupportsCustomDimensions = false,
    String? embeddingEndpointPath,
    int? embeddingBatchSize,
    bool embeddingRequiresSpecialBody = false,
    String? embeddingQueryModelId,
    String? embeddingDocumentModelId,
    List<String> embeddingInputTypes = const <String>[],
    String? embeddingDefaultInputType,
    String? embeddingQueryInputType,
    String? embeddingDocumentInputType,
    List<String> embeddingSupportedTaskTypes = const <String>[],
    String? embeddingDefaultTaskType,
    String? embeddingDefaultQueryTaskType,
    String? embeddingDefaultDocumentTaskType,
    String? embeddingQueryTextPrefix,
    String? embeddingDocumentTextPrefix,
    List<String> embeddingEncodingFormats = const <String>[],
    String? embeddingDefaultEncodingFormat,
    List<String> embeddingOutputDTypes = const <String>[],
    String? embeddingDefaultOutputDType,
    String? embeddingDefaultTruncation,
    String? embeddingSimilarityMetric,
    bool? embeddingOutputsNormalized,
    int? embeddingMinDimensions,
    int? embeddingMaxDimensions,
    int? embeddingMaxInputsPerBatch,
    int? embeddingMaxTokensPerBatch,
    bool embeddingSupportsTruncation = false,
  }) {
    return AiModelProfile(
      displayName: name,
      description: desc,
      isMultimodal: multimodal,
      supportsAttachments: supportsAttachments,
      requiresReasoningEcho: requiresReasoningEcho,
      supportedModalities: modalities,
      maxContextLength: context,
      maxSummaryLength: summary,
      maxOutputLength: output,
      maxThinkingLength: thinking,
      inputUsdPer1M: inputUsdPer1M,
      outputUsdPer1M: outputUsdPer1M,
      cacheReadUsdPer1M: cacheReadUsdPer1M,
      cacheWriteUsdPer1M: cacheWriteUsdPer1M,
      supportedParameters: supportedParameters,
      defaultParameters: defaultParameters,
      capabilities: capabilities,
      embeddingDimensions: embeddingDimensions,
      embeddingMaxInputTokens: embeddingMaxInputTokens,
      embeddingSupportsCustomDimensions: embeddingSupportsCustomDimensions,
      embeddingEndpointPath: embeddingEndpointPath,
      embeddingBatchSize: embeddingBatchSize,
      embeddingRequiresSpecialBody: embeddingRequiresSpecialBody,
      embeddingQueryModelId: embeddingQueryModelId,
      embeddingDocumentModelId: embeddingDocumentModelId,
      embeddingInputTypes: embeddingInputTypes,
      embeddingDefaultInputType: embeddingDefaultInputType,
      embeddingQueryInputType: embeddingQueryInputType,
      embeddingDocumentInputType: embeddingDocumentInputType,
      embeddingSupportedTaskTypes: embeddingSupportedTaskTypes,
      embeddingDefaultTaskType: embeddingDefaultTaskType,
      embeddingDefaultQueryTaskType: embeddingDefaultQueryTaskType,
      embeddingDefaultDocumentTaskType: embeddingDefaultDocumentTaskType,
      embeddingQueryTextPrefix: embeddingQueryTextPrefix,
      embeddingDocumentTextPrefix: embeddingDocumentTextPrefix,
      embeddingEncodingFormats: embeddingEncodingFormats,
      embeddingDefaultEncodingFormat: embeddingDefaultEncodingFormat,
      embeddingOutputDTypes: embeddingOutputDTypes,
      embeddingDefaultOutputDType: embeddingDefaultOutputDType,
      embeddingDefaultTruncation: embeddingDefaultTruncation,
      embeddingSimilarityMetric: embeddingSimilarityMetric,
      embeddingOutputsNormalized: embeddingOutputsNormalized,
      embeddingMinDimensions: embeddingMinDimensions,
      embeddingMaxDimensions: embeddingMaxDimensions,
      embeddingMaxInputsPerBatch: embeddingMaxInputsPerBatch,
      embeddingMaxTokensPerBatch: embeddingMaxTokensPerBatch,
      embeddingSupportsTruncation: embeddingSupportsTruncation,
    );
  }

  static AiModelProfile _embeddingP({
    required String name,
    String? desc,
    bool multimodal = false,
    Set<AiModelModality> modalities = const <AiModelModality>{
      AiModelModality.text,
    },
    int? context,
    required int dimensions,
    int? maxInputTokens,
    bool customDimensions = false,
    String? endpointPath,
    int? batchSize,
    bool specialBody = false,
    String? queryModelId,
    String? documentModelId,
    List<String> supportedParameters = _openAiCompatibleEmbeddingParameters,
    List<String> inputTypes = const <String>['text'],
    String? defaultInputType,
    String? queryInputType,
    String? documentInputType,
    List<String> taskTypes = const <String>[],
    String? defaultTaskType,
    String? queryTaskType,
    String? documentTaskType,
    String? queryTextPrefix,
    String? documentTextPrefix,
    List<String> encodingFormats = const <String>[],
    String? defaultEncodingFormat,
    List<String> outputDTypes = const <String>[],
    String? defaultOutputDType,
    String? defaultTruncation,
    String similarityMetric = 'cosine',
    bool? outputsNormalized,
    int? minDimensions,
    int? maxDimensions,
    int? maxInputsPerBatch,
    int? maxTokensPerBatch,
    bool supportsTruncation = false,
  }) {
    return _p(
      name: name,
      desc: desc,
      multimodal: multimodal,
      modalities: modalities,
      context: context ?? maxInputTokens,
      capabilities: _embeddingGen,
      supportedParameters: supportedParameters,
      embeddingDimensions: dimensions,
      embeddingMaxInputTokens: maxInputTokens ?? context,
      embeddingSupportsCustomDimensions: customDimensions,
      embeddingEndpointPath: endpointPath,
      embeddingBatchSize: batchSize,
      embeddingRequiresSpecialBody: specialBody,
      embeddingQueryModelId: queryModelId,
      embeddingDocumentModelId: documentModelId,
      embeddingInputTypes: inputTypes,
      embeddingDefaultInputType: defaultInputType,
      embeddingQueryInputType: queryInputType,
      embeddingDocumentInputType: documentInputType,
      embeddingSupportedTaskTypes: taskTypes,
      embeddingDefaultTaskType: defaultTaskType,
      embeddingDefaultQueryTaskType: queryTaskType,
      embeddingDefaultDocumentTaskType: documentTaskType,
      embeddingQueryTextPrefix: queryTextPrefix,
      embeddingDocumentTextPrefix: documentTextPrefix,
      embeddingEncodingFormats: encodingFormats,
      embeddingDefaultEncodingFormat: defaultEncodingFormat,
      embeddingOutputDTypes: outputDTypes,
      embeddingDefaultOutputDType: defaultOutputDType,
      embeddingDefaultTruncation: defaultTruncation,
      embeddingSimilarityMetric: similarityMetric,
      embeddingOutputsNormalized: outputsNormalized,
      embeddingMinDimensions: minDimensions,
      embeddingMaxDimensions: maxDimensions,
      embeddingMaxInputsPerBatch: maxInputsPerBatch,
      embeddingMaxTokensPerBatch: maxTokensPerBatch,
      embeddingSupportsTruncation: supportsTruncation,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OpenAI
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _openai(String id) {
    const imageParameters = <String>[
      'prompt',
      'size',
      'n',
      'quality',
      'style',
      'output_format',
      'background',
      'response_format',
    ];
    const videoParameters = <String>['prompt', 'size', 'seconds'];
    const audioParameters = <String>[
      'input',
      'voice',
      'response_format',
      'speed',
    ];

    // ── Video / audio generation ─────────────────────────────────────────
    if (id.startsWith('sora')) {
      return _p(
        name: 'Sora',
        desc: 'Video generation model',
        capabilities: _videoGen,
        supportedParameters: videoParameters,
      );
    }
    if (id.contains('tts') || id.contains('speech')) {
      return _p(
        name: 'OpenAI Audio',
        desc: 'Audio generation model',
        capabilities: _audioGen,
        supportedParameters: audioParameters,
      );
    }

    // ── Image generation ─────────────────────────────────────────────────
    if (id.startsWith('gpt-image') || id.startsWith('dall-e')) {
      return _p(
        name: id.startsWith('dall-e') ? 'DALL·E 3' : 'GPT Image',
        desc: 'Image generation model',
        capabilities: _imageGen,
        supportedParameters: imageParameters,
      );
    }

    // ── Embedding ────────────────────────────────────────────────────────
    if (id.startsWith('text-embedding-3-large')) {
      return _embeddingP(
        name: 'text-embedding-3-large',
        desc: 'OpenAI large text embedding model',
        context: 8192,
        dimensions: 3072,
        maxInputTokens: 8192,
        customDimensions: true,
        batchSize: 128,
        supportedParameters: _openAiEmbeddingParameters,
        encodingFormats: const <String>['float', 'base64'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
        minDimensions: 256,
        maxDimensions: 3072,
      );
    }
    if (id.startsWith('text-embedding-3-small')) {
      return _embeddingP(
        name: 'text-embedding-3-small',
        desc: 'OpenAI compact text embedding model',
        context: 8192,
        dimensions: 1536,
        maxInputTokens: 8192,
        customDimensions: true,
        batchSize: 128,
        supportedParameters: _openAiEmbeddingParameters,
        encodingFormats: const <String>['float', 'base64'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
        minDimensions: 256,
        maxDimensions: 1536,
      );
    }
    if (id.startsWith('text-embedding-ada-002')) {
      return _embeddingP(
        name: 'text-embedding-ada-002',
        desc: 'OpenAI legacy text embedding model',
        context: 8192,
        dimensions: 1536,
        maxInputTokens: 8192,
        batchSize: 128,
        supportedParameters: _openAiLegacyEmbeddingParameters,
        encodingFormats: const <String>['float', 'base64'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
      );
    }
    if (id.startsWith('text-embedding-') &&
        !id.startsWith('text-embedding-v') &&
        !id.startsWith('text-embedding-00')) {
      return _embeddingP(
        name: 'OpenAI Embedding',
        desc: 'OpenAI text embedding model',
        context: 8192,
        dimensions: 1536,
        maxInputTokens: 8192,
        customDimensions: true,
        batchSize: 128,
        supportedParameters: _openAiEmbeddingParameters,
        encodingFormats: const <String>['float', 'base64'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
      );
    }

    // ── Reasoning (o-series) — most specific first ───────────────────────
    if (id.startsWith('o4-mini')) {
      return _p(
        name: 'o4-mini',
        desc: '高效推理模型，支持视觉输入。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 200000,
        output: 100000,
        thinking: 100000,
        inputUsdPer1M: 1.10,
        outputUsdPer1M: 4.40,
        cacheReadUsdPer1M: 0.275,
      );
    }
    if (id.startsWith('o3-mini')) {
      return _p(
        name: 'o3-mini',
        desc: 'Compact reasoning model',
        context: 200000,
        output: 100000,
        thinking: 100000,
      );
    }
    if (id.startsWith('o3')) {
      return _p(
        name: 'o3',
        desc: '高级推理模型，支持视觉输入。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 200000,
        output: 100000,
        thinking: 100000,
        inputUsdPer1M: 2.00,
        outputUsdPer1M: 8.00,
        cacheReadUsdPer1M: 0.50,
      );
    }
    if (id.startsWith('o1-pro')) {
      return _p(
        name: 'o1-pro',
        desc: 'Enhanced reasoning for complex tasks',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 100000,
        thinking: 100000,
      );
    }
    if (id.startsWith('o1-mini')) {
      return _p(
        name: 'o1-mini',
        desc: 'Lightweight reasoning',
        context: 128000,
        output: 65536,
        thinking: 65536,
      );
    }
    if (id.startsWith('o1')) {
      return _p(
        name: 'o1',
        desc: 'Reasoning model with vision',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 100000,
        thinking: 100000,
      );
    }

    // ── GPT-5.5 / GPT-5.4 series ────────────────────────────────────────
    if (id.startsWith('gpt-5.5')) {
      return _p(
        name: 'GPT-5.5',
        desc: 'Flagship with 1M context, vision, and agentic tools',
        multimodal: true,
        modalities: _textImage,
        context: 1000000,
        output: 128000,
      );
    }
    if (id.startsWith('gpt-5.4-nano')) {
      return _p(
        name: 'GPT-5.4 Nano',
        desc: 'Ultra-efficient with 400K context',
        context: 400000,
        output: 128000,
      );
    }
    if (id.startsWith('gpt-5.4-mini')) {
      return _p(
        name: 'GPT-5.4 Mini',
        desc: 'Balanced model with 400K context and vision',
        multimodal: true,
        modalities: _textImage,
        context: 400000,
        output: 128000,
      );
    }
    if (id.startsWith('gpt-5.4')) {
      return _p(
        name: 'GPT-5.4',
        desc: 'Flagship with 1M context, vision, and reasoning',
        multimodal: true,
        modalities: _textImage,
        context: 1000000,
        output: 128000,
      );
    }

    // ── GPT-4.1 series ───────────────────────────────────────────────────
    if (id.startsWith('gpt-4.1-nano')) {
      return _p(
        name: 'GPT-4.1 Nano',
        desc: 'Ultra-efficient with 1M context',
        context: 1000000,
        output: 32768,
      );
    }
    if (id.startsWith('gpt-4.1-mini')) {
      return _p(
        name: 'GPT-4.1 Mini',
        desc: 'Balanced model with 1M context and vision',
        multimodal: true,
        modalities: _textImage,
        context: 1000000,
        output: 32768,
      );
    }
    if (id.startsWith('gpt-4.1')) {
      return _p(
        name: 'GPT-4.1',
        desc: '旗舰通用模型，支持 1M 上下文与视觉输入。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 1000000,
        output: 32768,
        inputUsdPer1M: 2.00,
        outputUsdPer1M: 8.00,
        cacheReadUsdPer1M: 0.50,
      );
    }

    // ── GPT-4o series ────────────────────────────────────────────────────
    if (id.startsWith('gpt-4o-mini')) {
      return _p(
        name: 'GPT-4o Mini',
        desc: 'Affordable and fast multimodal model',
        multimodal: true,
        modalities: _textImage,
        context: 128000,
        output: 16384,
      );
    }
    if (id.startsWith('gpt-4o') || id.startsWith('chatgpt-4o')) {
      return _p(
        name: 'GPT-4o',
        desc: 'Versatile multimodal model',
        multimodal: true,
        modalities: _textImage,
        context: 128000,
        output: 16384,
      );
    }

    // ── GPT-4 Turbo ──────────────────────────────────────────────────────
    if (id.startsWith('gpt-4-turbo')) {
      return _p(
        name: 'GPT-4 Turbo',
        desc: '128K context with vision',
        multimodal: true,
        modalities: _textImage,
        context: 128000,
        output: 4096,
      );
    }

    // ── Legacy GPT-4 ─────────────────────────────────────────────────────
    if (id.startsWith('gpt-4')) {
      return _p(
        name: 'GPT-4',
        desc: 'Foundational large language model',
        context: 8192,
        output: 4096,
      );
    }

    // ── GPT-3.5 ──────────────────────────────────────────────────────────
    if (id.startsWith('gpt-3.5')) {
      return _p(
        name: 'GPT-3.5 Turbo',
        desc: 'Fast and cost-effective',
        context: 16385,
        output: 4096,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Anthropic / Claude
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _claude(String id) {
    // ── Claude 4.7 / 4.6 / 4.5 ─────────────────────────────────────────
    if (id.contains('opus-4-7') || id.contains('4.7-opus')) {
      return _p(
        name: 'Claude Opus 4.7',
        desc: 'Most capable Claude model with extended thinking',
        multimodal: true,
        modalities: _textImage,
        context: 1000000,
        output: 128000,
        thinking: 128000,
      );
    }
    if (id.contains('sonnet-4-6') || id.contains('4.6-sonnet')) {
      return _p(
        name: 'Claude Sonnet 4.6',
        desc: '高性能 Claude 模型，支持 1M 上下文、扩展思考与视觉输入。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 1000000,
        output: 64000,
        thinking: 64000,
        inputUsdPer1M: 3.00,
        outputUsdPer1M: 15.00,
      );
    }
    if (id.contains('haiku-4-5') || id.contains('4.5-haiku')) {
      return _p(
        name: 'Claude Haiku 4.5',
        desc: 'Fast Claude 4.5 model with vision',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 64000,
      );
    }

    // ── Claude 4 ─────────────────────────────────────────────────────────
    if (id.startsWith('claude-4-opus') || id.startsWith('claude-opus-4')) {
      return _p(
        name: 'Claude 4 Opus',
        desc: 'Most capable model with extended thinking',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 32000,
        thinking: 128000,
      );
    }
    if (id.startsWith('claude-4-sonnet') || id.startsWith('claude-sonnet-4')) {
      return _p(
        name: 'Claude 4 Sonnet',
        desc: '高性能通用模型，支持扩展思考与视觉输入。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 200000,
        output: 64000,
        thinking: 128000,
        inputUsdPer1M: 3.00,
        outputUsdPer1M: 15.00,
      );
    }

    // ── Claude 3.7 ───────────────────────────────────────────────────────
    if (id.contains('3-7-sonnet') || id.contains('3.7-sonnet')) {
      return _p(
        name: 'Claude 3.7 Sonnet',
        desc: 'Extended thinking with vision',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 64000,
        thinking: 128000,
      );
    }

    // ── Claude 3.5 ───────────────────────────────────────────────────────
    if (id.contains('3-5-sonnet') || id.contains('3.5-sonnet')) {
      return _p(
        name: 'Claude 3.5 Sonnet',
        desc: 'Balanced performance with vision',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 8192,
      );
    }
    if (id.contains('3-5-haiku') || id.contains('3.5-haiku')) {
      return _p(
        name: 'Claude 3.5 Haiku',
        desc: 'Fast and affordable with vision',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 8192,
      );
    }

    // ── Claude 3 ─────────────────────────────────────────────────────────
    if (id.contains('3-opus')) {
      return _p(
        name: 'Claude 3 Opus',
        desc: 'Most capable Claude 3 model',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 4096,
      );
    }
    if (id.contains('3-sonnet')) {
      return _p(
        name: 'Claude 3 Sonnet',
        desc: 'Balanced Claude 3 model',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 4096,
      );
    }
    if (id.contains('3-haiku')) {
      return _p(
        name: 'Claude 3 Haiku',
        desc: 'Fastest Claude 3 model',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 4096,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Google Gemini
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _gemini(String id) {
    // ── Embedding ────────────────────────────────────────────────────────
    if (id.startsWith('gemini-embedding-2')) {
      return _embeddingP(
        name: 'Gemini Embedding 2',
        desc: 'Google multimodal embedding model',
        multimodal: true,
        modalities: _allModalities,
        context: 8192,
        dimensions: 3072,
        maxInputTokens: 8192,
        customDimensions: true,
        batchSize: 100,
        specialBody: true,
        supportedParameters: _geminiMultimodalEmbeddingParameters,
        inputTypes: const <String>['text', 'image', 'video', 'audio', 'file'],
        outputsNormalized: true,
        minDimensions: 128,
        maxDimensions: 3072,
      );
    }
    if (id.startsWith('gemini-embedding-001')) {
      return _embeddingP(
        name: 'Gemini Embedding 001',
        desc: 'Google Gemini text embedding model',
        context: 2048,
        dimensions: 3072,
        maxInputTokens: 2048,
        customDimensions: true,
        batchSize: 100,
        specialBody: true,
        supportedParameters: _geminiEmbeddingParameters,
        taskTypes: const <String>[
          'RETRIEVAL_QUERY',
          'RETRIEVAL_DOCUMENT',
          'SEMANTIC_SIMILARITY',
          'CLASSIFICATION',
          'CLUSTERING',
          'QUESTION_ANSWERING',
          'FACT_VERIFICATION',
          'CODE_RETRIEVAL_QUERY',
        ],
        defaultTaskType: 'RETRIEVAL_DOCUMENT',
        queryTaskType: 'RETRIEVAL_QUERY',
        documentTaskType: 'RETRIEVAL_DOCUMENT',
        outputsNormalized: true,
        minDimensions: 128,
        maxDimensions: 3072,
      );
    }
    if (id.startsWith('text-embedding-005')) {
      return _embeddingP(
        name: 'text-embedding-005',
        desc: 'Google text embedding model',
        context: 2048,
        dimensions: 768,
        maxInputTokens: 2048,
        customDimensions: true,
        batchSize: 100,
        specialBody: true,
        supportedParameters: _geminiEmbeddingParameters,
        taskTypes: const <String>[
          'RETRIEVAL_QUERY',
          'RETRIEVAL_DOCUMENT',
          'SEMANTIC_SIMILARITY',
          'CLASSIFICATION',
          'CLUSTERING',
          'QUESTION_ANSWERING',
          'FACT_VERIFICATION',
        ],
        defaultTaskType: 'RETRIEVAL_DOCUMENT',
        queryTaskType: 'RETRIEVAL_QUERY',
        documentTaskType: 'RETRIEVAL_DOCUMENT',
        outputsNormalized: true,
        minDimensions: 128,
        maxDimensions: 768,
      );
    }
    if (id.startsWith('text-multilingual-embedding-002')) {
      return _embeddingP(
        name: 'text-multilingual-embedding-002',
        desc: 'Google multilingual text embedding model',
        context: 2048,
        dimensions: 768,
        maxInputTokens: 2048,
        customDimensions: true,
        batchSize: 100,
        specialBody: true,
        supportedParameters: _geminiEmbeddingParameters,
        taskTypes: const <String>[
          'RETRIEVAL_QUERY',
          'RETRIEVAL_DOCUMENT',
          'SEMANTIC_SIMILARITY',
          'CLASSIFICATION',
          'CLUSTERING',
          'QUESTION_ANSWERING',
          'FACT_VERIFICATION',
        ],
        defaultTaskType: 'RETRIEVAL_DOCUMENT',
        queryTaskType: 'RETRIEVAL_QUERY',
        documentTaskType: 'RETRIEVAL_DOCUMENT',
        outputsNormalized: true,
        minDimensions: 128,
        maxDimensions: 768,
      );
    }
    if (id.startsWith('text-embedding-004')) {
      return _embeddingP(
        name: 'text-embedding-004',
        desc: 'Google text embedding model',
        context: 2048,
        dimensions: 768,
        maxInputTokens: 2048,
        customDimensions: true,
        batchSize: 100,
        specialBody: true,
        supportedParameters: _geminiEmbeddingParameters,
        taskTypes: const <String>[
          'RETRIEVAL_QUERY',
          'RETRIEVAL_DOCUMENT',
          'SEMANTIC_SIMILARITY',
          'CLASSIFICATION',
          'CLUSTERING',
          'QUESTION_ANSWERING',
          'FACT_VERIFICATION',
        ],
        defaultTaskType: 'RETRIEVAL_DOCUMENT',
        queryTaskType: 'RETRIEVAL_QUERY',
        documentTaskType: 'RETRIEVAL_DOCUMENT',
        outputsNormalized: true,
        minDimensions: 128,
        maxDimensions: 768,
      );
    }
    if (id == 'embedding-001' || id.startsWith('embedding-001')) {
      return _embeddingP(
        name: 'embedding-001',
        desc: 'Google legacy text embedding model',
        context: 2048,
        dimensions: 768,
        maxInputTokens: 2048,
        batchSize: 100,
        specialBody: true,
        supportedParameters: _geminiLegacyEmbeddingParameters,
        taskTypes: const <String>[
          'RETRIEVAL_QUERY',
          'RETRIEVAL_DOCUMENT',
          'SEMANTIC_SIMILARITY',
          'CLASSIFICATION',
          'CLUSTERING',
        ],
        defaultTaskType: 'RETRIEVAL_DOCUMENT',
        queryTaskType: 'RETRIEVAL_QUERY',
        documentTaskType: 'RETRIEVAL_DOCUMENT',
        outputsNormalized: true,
      );
    }

    // ── Gemini 2.5 ───────────────────────────────────────────────────────
    if (id.startsWith('gemini-2.5-pro')) {
      return _p(
        name: 'Gemini 2.5 Pro',
        desc: 'Gemini 旗舰模型，支持完整多模态、长上下文与思考能力。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _allModalities,
        context: 1048576,
        output: 65536,
        thinking: 65536,
        inputUsdPer1M: 1.25,
        outputUsdPer1M: 10.00,
      );
    }
    if (id.startsWith('gemini-2.5-flash-lite')) {
      return _p(
        name: 'Gemini 2.5 Flash-Lite',
        desc: 'Ultra-fast and cost-effective multimodal',
        multimodal: true,
        modalities: _allModalities,
        context: 1048576,
        output: 8192,
      );
    }
    if (id.startsWith('gemini-2.5-flash')) {
      return _p(
        name: 'Gemini 2.5 Flash',
        desc: '高性价比多模态模型，支持思考能力与 1M 上下文。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _allModalities,
        context: 1048576,
        output: 65536,
        thinking: 65536,
        inputUsdPer1M: 0.30,
        outputUsdPer1M: 2.50,
      );
    }

    // ── Gemini 2.0 ───────────────────────────────────────────────────────
    if (id.startsWith('gemini-2.0-flash')) {
      return _p(
        name: 'Gemini 2.0 Flash',
        desc: 'Multimodal with image generation',
        multimodal: true,
        modalities: _allModalities,
        context: 1048576,
        output: 8192,
        capabilities: _imageGen,
      );
    }

    // ── Gemini 1.5 ───────────────────────────────────────────────────────
    if (id.startsWith('gemini-1.5-pro')) {
      return _p(
        name: 'Gemini 1.5 Pro',
        desc: 'Multimodal with 2M context window',
        multimodal: true,
        modalities: _allModalities,
        context: 2097152,
        output: 8192,
      );
    }
    if (id.startsWith('gemini-1.5-flash')) {
      return _p(
        name: 'Gemini 1.5 Flash',
        desc: 'Fast and efficient multimodal',
        multimodal: true,
        modalities: _allModalities,
        context: 1048576,
        output: 8192,
      );
    }

    // ── Catch-all for newer Gemini versions (3.x+) ──────────────────────
    if (id.startsWith('gemini-')) {
      // Default multimodal profile for unknown Gemini models.
      return _p(
        name: 'Gemini',
        desc: 'Google multimodal model',
        multimodal: true,
        modalities: _allModalities,
        context: 1048576,
        output: 65536,
        thinking: 65536,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DeepSeek
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _deepseek(String id) {
    // ── V4 family ───────────────────────────────────────────────────────
    if (id.startsWith('deepseek-v4-flash')) {
      return _p(
        name: 'DeepSeek V4 Flash',
        desc: '新一代高速模型，支持可选思考模式与超长上下文。',
        supportsAttachments: false,
        requiresReasoningEcho: false,
        context: 1000000,
        output: 384000,
        thinking: 384000,
        inputUsdPer1M: 0.14,
        outputUsdPer1M: 0.28,
        cacheReadUsdPer1M: 0.0028,
      );
    }
    if (id.startsWith('deepseek-v4-pro') || id.startsWith('deepseek-v4')) {
      return _p(
        name: id.startsWith('deepseek-v4-pro')
            ? 'DeepSeek V4 Pro'
            : 'DeepSeek V4',
        desc: 'DeepSeek 新旗舰模型，支持长上下文与思考模式。',
        supportsAttachments: false,
        requiresReasoningEcho: true,
        context: 1000000,
        output: 384000,
        thinking: 384000,
        inputUsdPer1M: 0.435,
        outputUsdPer1M: 0.87,
        cacheReadUsdPer1M: 0.003625,
      );
    }

    // ── Distilled models ─────────────────────────────────────────────────
    if (id.startsWith('deepseek-r1-distill')) {
      return _p(
        name: 'DeepSeek R1 Distill',
        desc: 'Lightweight reasoning via distillation',
        context: 32768,
        output: 16384,
        thinking: 16384,
      );
    }

    // ── Reasoning models ─────────────────────────────────────────────────
    if (id.startsWith('deepseek-reasoner') || id.startsWith('deepseek-r1')) {
      return _p(
        name: id.startsWith('deepseek-reasoner')
            ? 'DeepSeek Reasoner'
            : 'DeepSeek R1',
        desc: '深度推理模型，适合复杂思考任务。',
        supportsAttachments: false,
        requiresReasoningEcho: true,
        context: 131072,
        output: 65536,
        thinking: 32768,
      );
    }

    // ── V3.2 (latest) ────────────────────────────────────────────────────
    if (id.startsWith('deepseek-v3.2') || id.startsWith('deepseek-v3-2')) {
      return _p(
        name: 'DeepSeek V3.2',
        desc: 'Latest generation with thinking support',
        context: 131072,
        output: 65536,
        thinking: 32768,
      );
    }

    // ── V3.1 ─────────────────────────────────────────────────────────────
    if (id.startsWith('deepseek-v3.1') || id.startsWith('deepseek-v3-1')) {
      return _p(
        name: 'DeepSeek V3.1',
        desc: 'Improved chat model',
        context: 131072,
        output: 16384,
      );
    }

    // ── V3 ───────────────────────────────────────────────────────────────
    if (id.startsWith('deepseek-v3')) {
      return _p(
        name: 'DeepSeek V3',
        desc: 'Powerful open-source model',
        context: 131072,
        output: 16384,
      );
    }

    // ── Generic chat ─────────────────────────────────────────────────────
    if (id.startsWith('deepseek-chat')) {
      return _p(
        name: 'DeepSeek Chat',
        desc: 'General-purpose chat model',
        context: 131072,
        output: 8192,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Qwen (Alibaba Cloud / 通义千问)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _qwen(String id) {
    const imageParameters = <String>[
      'prompt',
      'size',
      'n',
      'negative_prompt',
      'seed',
      'prompt_extend',
      'watermark',
      'response_format',
    ];
    const videoParameters = <String>[
      'input.prompt',
      'parameters.size',
      'parameters.duration',
      'parameters.negative_prompt',
      'parameters.seed',
      'parameters.prompt_extend',
      'parameters.watermark',
    ];
    const audioParameters = <String>[
      'input.text',
      'parameters.voice',
      'parameters.format',
      'parameters.speed',
      'parameters.sample_rate',
    ];

    // ── Embedding ────────────────────────────────────────────────────────
    if (id.startsWith('text-embedding-v4')) {
      return _embeddingP(
        name: 'text-embedding-v4',
        desc: 'Qwen3 text embedding model',
        context: 8192,
        dimensions: 1024,
        maxInputTokens: 8192,
        customDimensions: true,
        endpointPath: 'compatible-mode/v1/embeddings',
        batchSize: 10,
        supportedParameters: _qwenTextEmbeddingParameters,
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
        minDimensions: 512,
        maxDimensions: 2048,
      );
    }
    if (id.startsWith('text-embedding-v3')) {
      return _embeddingP(
        name: 'text-embedding-v3',
        desc: 'Qwen text embedding model',
        context: 8192,
        dimensions: 1024,
        maxInputTokens: 8192,
        customDimensions: true,
        endpointPath: 'compatible-mode/v1/embeddings',
        batchSize: 10,
        supportedParameters: _qwenTextEmbeddingParameters,
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
        minDimensions: 512,
        maxDimensions: 1024,
      );
    }
    if (id.startsWith('text-embedding-v')) {
      return _embeddingP(
        name: 'Qwen Text Embedding',
        desc: 'DashScope text embedding model',
        context: 8192,
        dimensions: 1024,
        maxInputTokens: 8192,
        endpointPath: 'compatible-mode/v1/embeddings',
        batchSize: 10,
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
      );
    }
    if (id.startsWith('qwen3-vl-embedding')) {
      return _embeddingP(
        name: 'Qwen3-VL Embedding',
        desc: 'DashScope multimodal fused embedding model',
        multimodal: true,
        modalities: _textImageVideo,
        context: 32000,
        dimensions: 2560,
        maxInputTokens: 32000,
        customDimensions: true,
        endpointPath:
            'api/v1/services/embeddings/multimodal-embedding/multimodal-embedding',
        batchSize: 1,
        supportedParameters: _qwenMultimodalEmbeddingParameters,
        inputTypes: const <String>['text', 'image', 'video'],
        minDimensions: 32,
        maxDimensions: 2560,
      );
    }
    if (id.startsWith('tongyi-embedding-vision-plus')) {
      return _embeddingP(
        name: 'Tongyi Embedding Vision Plus',
        desc: 'DashScope independent multimodal embedding model',
        multimodal: true,
        modalities: _textImageVideo,
        context: 1024,
        dimensions: 1152,
        maxInputTokens: 1024,
        customDimensions: true,
        endpointPath:
            'api/v1/services/embeddings/multimodal-embedding/multimodal-embedding',
        batchSize: 1,
        inputTypes: const <String>['text', 'image', 'video'],
        maxDimensions: 1152,
      );
    }
    if (id.startsWith('tongyi-embedding-vision-flash') ||
        id.startsWith('multimodal-embedding-v1')) {
      return _embeddingP(
        name: id.startsWith('tongyi-embedding-vision-flash')
            ? 'Tongyi Embedding Vision Flash'
            : 'multimodal-embedding-v1',
        desc: 'DashScope multimodal embedding model',
        multimodal: true,
        modalities: _textImageVideo,
        context: id.startsWith('multimodal-embedding-v1') ? 512 : 1024,
        dimensions: id.startsWith('multimodal-embedding-v1') ? 1024 : 768,
        maxInputTokens: id.startsWith('multimodal-embedding-v1') ? 512 : 1024,
        customDimensions: true,
        endpointPath:
            'api/v1/services/embeddings/multimodal-embedding/multimodal-embedding',
        batchSize: 1,
        inputTypes: const <String>['text', 'image', 'video'],
        maxDimensions: id.startsWith('multimodal-embedding-v1') ? 1024 : 768,
      );
    }

    // ── Image / video / audio generation ─────────────────────────────────
    if (id.startsWith('qwen-image')) {
      return _p(
        name: 'Qwen Image',
        desc: 'Image generation',
        capabilities: _imageGen,
        supportedParameters: imageParameters,
      );
    }
    if (id.startsWith('wan')) {
      return _p(
        name: 'Wanxiang',
        desc: 'Video generation',
        capabilities: _videoGen,
        supportedParameters: videoParameters,
      );
    }
    if (id.startsWith('qwen-tts') ||
        id.startsWith('qwen3-tts') ||
        id.startsWith('qwen2-tts') ||
        id.contains('cosyvoice')) {
      return _p(
        name: 'Qwen Audio',
        desc: 'Audio generation',
        capabilities: _audioGen,
        supportedParameters: audioParameters,
      );
    }

    // ── Omni (text + image + video + audio) ──────────────────────────────
    if (id.startsWith('qwen3.5-omni')) {
      return _p(
        name: id.contains('flash') ? 'Qwen3.5 Omni Flash' : 'Qwen3.5 Omni Plus',
        desc: 'Full multimodal: text, image, video, audio I/O',
        multimodal: true,
        modalities: _allModalities,
        context: 262144,
        output: 65536,
      );
    }
    if (id.startsWith('qwen3-omni') || id.startsWith('qwen2.5-omni')) {
      return _p(
        name: 'Qwen Omni Flash',
        desc: 'Lightweight full multimodal with thinking',
        multimodal: true,
        modalities: _allModalities,
        context: 65536,
        output: 16384,
        thinking: 32768,
      );
    }

    // ── Visual reasoning (QVQ) ───────────────────────────────────────────
    if (id.startsWith('qvq-max') || id.startsWith('qvq-plus')) {
      return _p(
        name: id.startsWith('qvq-max') ? 'QVQ-Max' : 'QVQ-Plus',
        desc: 'Visual reasoning model',
        multimodal: true,
        modalities: _textImage,
        context: 131072,
        output: 8192,
        thinking: 16384,
      );
    }
    if (id.startsWith('qvq-72b')) {
      return _p(
        name: 'QVQ-72B',
        desc: 'Open-source visual reasoning (preview)',
        multimodal: true,
        modalities: _textImage,
        context: 32768,
        output: 16384,
      );
    }

    // ── Vision (千问VL) ──────────────────────────────────────────────────
    if (id.startsWith('qwen3-vl-plus')) {
      return _p(
        name: 'Qwen3-VL Plus',
        desc: 'Vision understanding with thinking',
        multimodal: true,
        modalities: _textImageVideo,
        context: 262144,
        output: 32768,
        thinking: 81920,
      );
    }
    if (id.startsWith('qwen3-vl-flash')) {
      return _p(
        name: 'Qwen3-VL Flash',
        desc: 'Fast vision understanding with thinking',
        multimodal: true,
        modalities: _textImageVideo,
        context: 262144,
        output: 32768,
        thinking: 81920,
      );
    }
    if (id.startsWith('qwen3-vl-') || id.startsWith('qwen2.5-vl-')) {
      return _p(
        name: 'Qwen-VL',
        desc: 'Open-source vision model',
        multimodal: true,
        modalities: _textImageVideo,
        context: 131072,
        output: 32768,
      );
    }

    // ── OCR ──────────────────────────────────────────────────────────────
    if (id.startsWith('qwen-vl-ocr')) {
      return _p(
        name: 'Qwen-VL OCR',
        desc: 'Specialized document text extraction',
        multimodal: true,
        modalities: _textImage,
        context: 38192,
        output: 8192,
      );
    }

    // ── Audio ────────────────────────────────────────────────────────────
    if (id.startsWith('qwen-audio') || id.startsWith('qwen3-audio')) {
      return _p(
        name: 'Qwen Audio',
        desc: 'Audio understanding model',
        multimodal: true,
        modalities: <AiModelModality>{
          AiModelModality.text,
          AiModelModality.audio,
        },
        context: 8192,
        output: 2048,
      );
    }

    // ── Reasoning (QwQ) ──────────────────────────────────────────────────
    if (id.startsWith('qwq-plus')) {
      return _p(
        name: 'QwQ-Plus',
        desc: 'Advanced reasoning model',
        context: 131072,
        output: 8192,
        thinking: 32768,
      );
    }
    if (id.startsWith('qwq-32b')) {
      return _p(
        name: 'QwQ-32B',
        desc: 'Open-source reasoning model',
        context: 131072,
        output: 8192,
        thinking: 32768,
      );
    }

    // ── Coder ────────────────────────────────────────────────────────────
    if (id.startsWith('qwen3-coder')) {
      return _p(
        name: id.contains('flash') ? 'Qwen3 Coder Flash' : 'Qwen3 Coder Plus',
        desc: 'Specialized coding agent',
        context: 1000000,
        output: 65536,
      );
    }

    // ── Max (flagship text) ──────────────────────────────────────────────
    if (id.startsWith('qwen3-max')) {
      return _p(
        name: 'Qwen3-Max',
        desc: '通义千问旗舰模型，适合复杂任务与长上下文推理。',
        supportsAttachments: false,
        context: 262144,
        output: 65536,
        thinking: 81920,
      );
    }

    // ── Plus (text or multimodal) ────────────────────────────────────────
    if (id.startsWith('qwen3.6-plus')) {
      return _p(
        name: 'Qwen3.6-Plus',
        desc: 'Multimodal: text, image, video input',
        multimodal: true,
        modalities: _textImageVideo,
        context: 1000000,
        output: 65536,
        thinking: 81920,
      );
    }
    if (id.startsWith('qwen3.5-plus')) {
      return _p(
        name: 'Qwen3.5-Plus',
        desc: '通义千问高阶多模态模型，支持图像/视频输入与长上下文。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImageVideo,
        context: 1000000,
        output: 65536,
        thinking: 81920,
      );
    }
    if (id.startsWith('qwen-plus')) {
      return _p(
        name: 'Qwen-Plus',
        desc: '通义千问均衡文本模型，支持长上下文与思考能力。',
        supportsAttachments: false,
        context: 1000000,
        output: 32768,
        thinking: 81920,
      );
    }

    // ── Flash (fast text) ────────────────────────────────────────────────
    if (id.startsWith('qwen3.6-flash')) {
      return _p(
        name: 'Qwen3.6-Flash',
        desc: 'Fast and cost-effective',
        context: 1000000,
        output: 65536,
        thinking: 81920,
      );
    }
    if (id.startsWith('qwen3.5-flash')) {
      return _p(
        name: 'Qwen3.5-Flash',
        desc: 'Fast and cost-effective',
        context: 1000000,
        output: 65536,
        thinking: 81920,
      );
    }
    if (id.startsWith('qwen-flash')) {
      return _p(
        name: 'Qwen-Flash',
        desc: 'Fast text model with thinking',
        context: 1000000,
        output: 32768,
        thinking: 81920,
      );
    }

    // ── Turbo ────────────────────────────────────────────────────────────
    if (id.startsWith('qwen-turbo')) {
      return _p(
        name: 'Qwen-Turbo',
        desc: '通义千问高速文本模型，偏向低时延与高吞吐。',
        supportsAttachments: false,
        context: 1000000,
        output: 16384,
      );
    }

    // ── Long ─────────────────────────────────────────────────────────────
    if (id.startsWith('qwen-long')) {
      return _p(
        name: 'Qwen-Long',
        desc: 'Ultra-long 10M context window',
        context: 10000000,
        output: 32768,
      );
    }

    // ── Open-source Qwen3 sizes ──────────────────────────────────────────
    if (id.startsWith('qwen3-235b') || id.startsWith('qwen3-next')) {
      return _p(
        name: 'Qwen3-235B',
        desc: 'Large open-source model',
        context: 131072,
        output: 16384,
        thinking: 38912,
      );
    }
    if (id.startsWith('qwen3-32b') ||
        id.startsWith('qwen3-30b') ||
        id.startsWith('qwen3-14b') ||
        id.startsWith('qwen3-8b') ||
        id.startsWith('qwen3-4b')) {
      return _p(
        name: 'Qwen3',
        desc: 'Open-source model with thinking',
        context: 131072,
        output: 8192,
        thinking: 38912,
      );
    }
    if (id.startsWith('qwen3-1.7b') || id.startsWith('qwen3-0.6b')) {
      return _p(
        name: 'Qwen3',
        desc: 'Compact open-source model',
        context: 32768,
        output: 2048,
      );
    }

    // ── Open-source Qwen3.5/3.6 ─────────────────────────────────────────
    if (id.startsWith('qwen3.6-') || id.startsWith('qwen3.5-')) {
      return _p(
        name: id.startsWith('qwen3.6') ? 'Qwen3.6' : 'Qwen3.5',
        desc: 'Open-source model with thinking',
        context: 262144,
        output: 65536,
        thinking: 81920,
      );
    }

    // ── Qwen2.5 (previous gen) ───────────────────────────────────────────
    if (id.startsWith('qwen2.5-')) {
      return _p(
        name: 'Qwen2.5',
        desc: 'Previous generation model',
        context: 131072,
        output: 8192,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GLM (Zhipu AI / 智谱)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _glm(String id) {
    // ── Embedding ────────────────────────────────────────────────────────
    if (id.startsWith('embedding-3')) {
      return _embeddingP(
        name: 'Embedding-3',
        desc: 'Zhipu AI text embedding model',
        context: 8192,
        dimensions: 2048,
        maxInputTokens: 8192,
        customDimensions: true,
        endpointPath: 'api/paas/v4/embeddings',
        batchSize: 64,
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
        minDimensions: 256,
        maxDimensions: 2048,
      );
    }
    if (id.startsWith('embedding-2') || id == 'embedding') {
      return _embeddingP(
        name: 'GLM Embedding',
        desc: 'Zhipu AI text embedding model',
        context: 8192,
        dimensions: 1024,
        maxInputTokens: 8192,
        endpointPath: 'api/paas/v4/embeddings',
        batchSize: 64,
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
      );
    }

    // ── Image / Video generation ─────────────────────────────────────────
    if (id.startsWith('cogview')) {
      return _p(
        name: 'CogView',
        desc: 'Image generation',
        capabilities: _imageGen,
      );
    }
    if (id.startsWith('cogvideo')) {
      return _p(
        name: 'CogVideoX',
        desc: 'Video generation',
        capabilities: _videoGen,
      );
    }
    if (id.startsWith('cogtts') || id.startsWith('cogsound')) {
      return _p(
        name: 'CogTTS',
        desc: 'Audio generation',
        capabilities: _audioGen,
      );
    }

    // ── Vision models ────────────────────────────────────────────────────
    if (id.startsWith('glm-5v')) {
      return _p(
        name: 'GLM-5V Turbo',
        desc: 'Vision understanding model',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 128000,
      );
    }
    if (id.contains('4.6v-flash') || id.contains('4-6v-flash')) {
      return _p(
        name: 'GLM-4.6V Flash',
        desc: 'Free vision model',
        multimodal: true,
        modalities: _textImage,
        context: 128000,
        output: 32000,
      );
    }
    if (id.contains('4.6v') || id.contains('4-6v')) {
      return _p(
        name: 'GLM-4.6V',
        desc: '智谱视觉理解模型，支持图像输入。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 128000,
        output: 32000,
      );
    }
    if (id.contains('4.5v') || id.contains('4-5v')) {
      return _p(
        name: 'GLM-4.5V',
        desc: '智谱视觉理解模型，支持图像输入。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 64000,
        output: 16000,
        inputUsdPer1M: 0.60,
        outputUsdPer1M: 1.80,
        cacheReadUsdPer1M: 0.11,
      );
    }
    if (id.startsWith('glm-4v')) {
      return _p(
        name: 'GLM-4V Flash',
        desc: 'Lightweight free vision model',
        multimodal: true,
        modalities: _textImage,
        context: 16000,
        output: 1000,
      );
    }

    // ── Code model ───────────────────────────────────────────────────────
    if (id.startsWith('codegeex')) {
      return _p(
        name: 'CodeGeeX-4',
        desc: 'Code generation model',
        context: 128000,
        output: 32000,
      );
    }

    // ── Text models (newest first) ───────────────────────────────────────
    if (id.startsWith('glm-5.1') || id.startsWith('glm-5-1')) {
      return _p(
        name: 'GLM-5.1',
        desc: '智谱当前旗舰模型，强调深度思考与长上下文。',
        supportsAttachments: false,
        context: 200000,
        output: 128000,
        thinking: 128000,
      );
    }
    if (id.startsWith('glm-5-turbo') || id.startsWith('glm-5turbo')) {
      return _p(
        name: 'GLM-5 Turbo',
        desc: 'Fast flagship model',
        context: 200000,
        output: 128000,
      );
    }
    if (id.startsWith('glm-5')) {
      return _p(
        name: 'GLM-5',
        desc: '智谱旗舰文本模型。',
        supportsAttachments: false,
        context: 200000,
        output: 128000,
      );
    }
    if (id.contains('4.7-flash') || id.contains('4-7-flash')) {
      return _p(
        name: 'GLM-4.7 Flash',
        desc: 'Free fast model',
        context: 200000,
        output: 128000,
      );
    }
    if (id.startsWith('glm-4.7') || id.startsWith('glm-4-7')) {
      return _p(
        name: 'GLM-4.7',
        desc: 'Balanced model with thinking',
        context: 200000,
        output: 128000,
      );
    }
    if (id.startsWith('glm-4.6') || id.startsWith('glm-4-6')) {
      return _p(
        name: 'GLM-4.6',
        desc: 'Capable model with thinking',
        context: 200000,
        output: 128000,
      );
    }
    if (id.contains('4.5-air') || id.contains('4-5-air')) {
      return _p(
        name: 'GLM-4.5 Air',
        desc: '高性价比文本模型。',
        supportsAttachments: false,
        context: 128000,
        output: 96000,
      );
    }
    if (id.startsWith('glm-4.5') || id.startsWith('glm-4-5')) {
      return _p(
        name: 'GLM-4.5',
        desc: '智谱高阶文本模型。',
        supportsAttachments: false,
        context: 128000,
        output: 96000,
        inputUsdPer1M: 0.60,
        outputUsdPer1M: 2.20,
        cacheReadUsdPer1M: 0.11,
      );
    }
    if (id.startsWith('glm-4-long')) {
      return _p(
        name: 'GLM-4 Long',
        desc: 'Ultra-long 1M context',
        context: 1000000,
        output: 4000,
      );
    }
    if (id.startsWith('glm-4-flashx')) {
      return _p(
        name: 'GLM-4 FlashX',
        desc: 'Fast text model',
        context: 128000,
        output: 16000,
      );
    }
    if (id.startsWith('glm-4')) {
      return _p(
        name: 'GLM-4',
        desc: 'Previous generation model',
        context: 128000,
        output: 4000,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Kimi / Moonshot (月之暗面)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _kimi(String id) {
    if (id.contains('kimi-k2.6') || id.contains('kimi-k2-6')) {
      return _p(
        name: 'Kimi K2.6',
        desc: 'Kimi 当前旗舰推理与 Agent 模型。',
        supportsAttachments: false,
        context: 262144,
        output: 98304,
        thinking: 81920,
        inputUsdPer1M: 0.95,
        outputUsdPer1M: 4.00,
        cacheReadUsdPer1M: 0.16,
      );
    }
    if (id.contains('kimi-k2.5') || id.contains('kimi-k2-5')) {
      return _p(
        name: 'Kimi K2.5',
        desc: 'Kimi 高阶推理模型。',
        supportsAttachments: false,
        context: 262144,
        output: 98304,
        thinking: 81920,
        inputUsdPer1M: 0.60,
        outputUsdPer1M: 3.00,
        cacheReadUsdPer1M: 0.10,
      );
    }
    if (id.contains('k2-thinking')) {
      return _p(
        name: 'Kimi K2 Thinking',
        desc: 'Deep thinking model',
        context: 262144,
        output: 16384,
        thinking: 32768,
      );
    }
    if (id.contains('k2-instruct') || id.contains('k2-chat')) {
      return _p(
        name: 'Kimi K2 Instruct',
        desc: 'Instruction-following model',
        context: 131072,
        output: 8192,
      );
    }
    if (id.startsWith('moonshot-v1-128k')) {
      return _p(
        name: 'Moonshot v1 128K',
        desc: 'Long-context model',
        context: 128000,
        output: 8192,
      );
    }
    if (id.startsWith('moonshot-v1-32k')) {
      return _p(
        name: 'Moonshot v1 32K',
        desc: 'Medium-context model',
        context: 32000,
        output: 8192,
      );
    }
    if (id.startsWith('moonshot-v1') || id.startsWith('moonshot')) {
      return _p(
        name: 'Moonshot v1',
        desc: 'Standard model',
        context: 8000,
        output: 4096,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Seed / Doubao (火山引擎 / 字节跳动)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _seed(String id) {
    const imageParameters = <String>[
      'prompt',
      'size',
      'aspect_ratio',
      'negative_prompt',
      'seed',
      'watermark',
      'output_format',
      'response_format',
    ];
    const videoParameters = <String>[
      'prompt',
      'aspect_ratio',
      'size',
      'duration',
      'duration_seconds',
      'resolution',
      'frame_rate',
      'fps',
      'num_frames',
      'negative_prompt',
      'seed',
      'prompt_extend',
      'watermark',
      'mode',
    ];

    // ── Image generation ─────────────────────────────────────────────────
    if (id.contains('seedream')) {
      return _p(
        name: 'Seedream',
        desc: 'Image generation',
        capabilities: _imageGen,
        supportedParameters: imageParameters,
      );
    }

    // ── Video generation ─────────────────────────────────────────────────
    if (id.contains('seedance')) {
      return _p(
        name: 'Seedance',
        desc: 'Video generation',
        capabilities: _videoGen,
        supportedParameters: videoParameters,
      );
    }

    // ── Seed 2.0 (latest flagship) ───────────────────────────────────────
    if (id.contains('seed-2-0') || id.contains('seed-2.0')) {
      final String suffix;
      if (id.contains('code')) {
        suffix = ' Code';
      } else if (id.contains('mini')) {
        suffix = ' Mini';
      } else if (id.contains('lite')) {
        suffix = ' Lite';
      } else if (id.contains('pro')) {
        suffix = ' Pro';
      } else {
        suffix = '';
      }
      return _p(
        name: 'Doubao Seed 2.0$suffix',
        desc: 'Flagship agent model with multimodal',
        multimodal: true,
        modalities: _textImage,
        context: 256000,
        output: 128000,
        thinking: 128000,
      );
    }

    // ── Seed 1.8 ─────────────────────────────────────────────────────────
    if (id.contains('seed-1-8') || id.contains('seed-1.8')) {
      return _p(
        name: 'Doubao Seed 1.8',
        desc: 'Multimodal agent model',
        multimodal: true,
        modalities: _textImage,
        context: 256000,
        output: 32000,
        thinking: 32000,
      );
    }

    // ── Seed 1.6 vision ──────────────────────────────────────────────────
    if (id.contains('seed-1-6-vision') || id.contains('seed-1.6-vision')) {
      return _p(
        name: 'Doubao Seed 1.6 Vision',
        desc: 'Multimodal with GUI task support',
        multimodal: true,
        modalities: _textImage,
        context: 256000,
        output: 32000,
        thinking: 32000,
      );
    }

    // ── Seed 1.6 variants ────────────────────────────────────────────────
    if (id.contains('seed-1-6') || id.contains('seed-1.6')) {
      final String suffix;
      if (id.contains('flash')) {
        suffix = ' Flash';
      } else if (id.contains('lite')) {
        suffix = ' Lite';
      } else {
        suffix = '';
      }
      return _p(
        name: 'Doubao Seed 1.6$suffix',
        desc: '豆包多模态 Agent 模型。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 256000,
        output: 32000,
        thinking: 32000,
        inputUsdPer1M: id.contains('flash') ? 0.15 : 0.80,
        outputUsdPer1M: id.contains('flash') ? 1.50 : 2.00,
      );
    }

    // ── Seed code preview ────────────────────────────────────────────────
    if (id.contains('seed-code')) {
      return _p(
        name: 'Doubao Seed Code',
        desc: 'Coding-enhanced model',
        multimodal: true,
        modalities: _textImage,
        context: 256000,
        output: 32000,
        thinking: 32000,
      );
    }

    // ── Character model ──────────────────────────────────────────────────
    if (id.contains('character')) {
      return _p(
        name: 'Doubao Character',
        desc: 'Role-play optimized model',
        context: 128000,
        output: 32000,
      );
    }

    // ── Doubao 1.5 series ────────────────────────────────────────────────
    if (id.contains('1-5-vision') || id.contains('1.5-vision')) {
      return _p(
        name: 'Doubao 1.5 Vision Pro',
        desc: 'Vision understanding',
        multimodal: true,
        modalities: _textImage,
        context: 32000,
        output: 12000,
      );
    }
    if (id.contains('1-5-lite') || id.contains('1.5-lite')) {
      return _p(
        name: 'Doubao 1.5 Lite',
        desc: 'Lightweight text model',
        context: 32000,
        output: 12000,
      );
    }
    if (id.contains('1-5-pro') || id.contains('1.5-pro')) {
      return _p(
        name: 'Doubao 1.5 Pro',
        desc: '豆包高阶文本模型。',
        supportsAttachments: false,
        context: 128000,
        output: 16000,
      );
    }

    // ── Embedding ────────────────────────────────────────────────────────
    if (id.contains('doubao-embedding') ||
        id.contains('embedding-text') ||
        id.contains('embedding-vision')) {
      return _embeddingP(
        name: 'Doubao Embedding',
        desc: 'Text/multimodal embedding model',
        context: 128000,
        dimensions: 2048,
        maxInputTokens: 128000,
        endpointPath: 'api/v3/embeddings',
        batchSize: 64,
        inputTypes: const <String>['text', 'image'],
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // StepFun (阶跃星辰)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _stepfun(String id) {
    const imageParameters = <String>[
      'prompt',
      'size',
      'n',
      'response_format',
      'seed',
      'steps',
      'cfg_scale',
      'negative_prompt',
      'text_mode',
      'style_reference',
    ];
    const audioParameters = <String>[
      'input',
      'voice',
      'response_format',
      'speed',
      'volume',
      'sample_rate',
      'voice_label',
      'instruction',
      'pronunciation_map',
      'stream_format',
      'return_url',
    ];

    if (id.startsWith('step-image') ||
        id.startsWith('step-2x') ||
        id.startsWith('step-1x')) {
      return _p(
        name: 'Step Image',
        desc: '阶跃星辰图片生成/编辑模型。',
        capabilities: _imageGen,
        supportedParameters: imageParameters,
      );
    }
    if (id.contains('tts') || id.startsWith('stepaudio-2.5-tts')) {
      return _p(
        name: 'StepAudio TTS',
        desc: '阶跃星辰语音合成模型。',
        capabilities: _audioGen,
        supportedParameters: audioParameters,
      );
    }
    // ── Vision models (check before text) ────────────────────────────────
    if (id.startsWith('step-3.7') || id.startsWith('step-3-7')) {
      return _p(
        name: 'Step 3.7 Flash',
        desc: '阶跃星辰旗舰多模态推理模型。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImageVideo,
        context: _parseStepContext(id) ?? 256000,
        output: 32768,
        thinking: 32768,
      );
    }
    if (id.startsWith('stepaudio-2.5-chat')) {
      return _p(
        name: 'StepAudio 2.5 Chat',
        desc: '阶跃星辰音频对话模型。',
        multimodal: true,
        supportsAttachments: true,
        modalities: const <AiModelModality>{
          AiModelModality.text,
          AiModelModality.audio,
        },
        context: _parseStepContext(id) ?? 128000,
        output: 8192,
      );
    }
    if (id.startsWith('step-2v') || id.startsWith('step-1.5v')) {
      return _p(
        name: 'Step Vision',
        desc: 'Vision understanding model',
        multimodal: true,
        modalities: _textImage,
        context: _parseStepContext(id),
        output: 4096,
      );
    }
    if (id.startsWith('step-1v')) {
      return _p(
        name: 'Step-1V',
        desc: 'Vision understanding model',
        multimodal: true,
        modalities: _textImage,
        context: _parseStepContext(id),
        output: 4096,
      );
    }

    // ── Text models ──────────────────────────────────────────────────────
    if (id.startsWith('step-3')) {
      return _p(
        name: 'Step-3',
        desc: '阶跃星辰文本主力模型。',
        supportsAttachments: false,
        context: _parseStepContext(id) ?? 65536,
        output: 4096,
      );
    }
    if (id.startsWith('step-2')) {
      return _p(
        name: 'Step-2',
        desc: '阶跃星辰上一代旗舰文本模型。',
        supportsAttachments: false,
        context: _parseStepContext(id),
        output: 4096,
      );
    }
    if (id.startsWith('step-1')) {
      return _p(
        name: 'Step-1',
        desc: 'Text generation model',
        context: _parseStepContext(id),
        output: 4096,
      );
    }

    return null;
  }

  /// Extract context size from StepFun model IDs like `step-2-16k`.
  static int? _parseStepContext(String id) {
    final match = RegExp(r'(\d+)k').firstMatch(id);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 1024;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Mistral AI
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _mistral(String id) {
    if (id.startsWith('codestral-embed')) {
      return _embeddingP(
        name: 'Codestral Embed',
        desc: 'Mistral code embedding model',
        context: 8192,
        dimensions: 1536,
        maxInputTokens: 8192,
        customDimensions: true,
        batchSize: 64,
        supportedParameters: _mistralEmbeddingParameters,
        inputTypes: const <String>['text', 'code'],
        outputDTypes: const <String>['float', 'int8', 'uint8', 'binary'],
        defaultOutputDType: 'float',
        minDimensions: 256,
        maxDimensions: 1536,
      );
    }
    if (id.startsWith('mistral-embed')) {
      return _embeddingP(
        name: 'Mistral Embed',
        desc: 'Mistral text embedding model',
        context: 8192,
        dimensions: 1024,
        maxInputTokens: 8192,
        customDimensions: true,
        batchSize: 64,
        supportedParameters: _mistralEmbeddingParameters,
        outputDTypes: const <String>['float', 'int8', 'uint8', 'binary'],
        defaultOutputDType: 'float',
        minDimensions: 256,
        maxDimensions: 1024,
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Cohere
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile _cohereTextEmbedV3({
    required String name,
    required String desc,
    required int dimensions,
  }) {
    return _embeddingP(
      name: name,
      desc: desc,
      context: 512,
      dimensions: dimensions,
      maxInputTokens: 512,
      endpointPath: 'v2/embed',
      batchSize: 96,
      supportedParameters: _cohereEmbeddingParameters,
      inputTypes: const <String>['search_document', 'search_query'],
      defaultInputType: 'search_document',
      queryInputType: 'search_query',
      documentInputType: 'search_document',
      taskTypes: const <String>[
        'search_document',
        'search_query',
        'classification',
        'clustering',
      ],
      defaultTruncation: 'END',
      maxInputsPerBatch: 96,
      supportsTruncation: true,
    );
  }

  static AiModelProfile? _cohere(String id) {
    if (id.contains('embed-v4') || id.contains('embed-4')) {
      return _embeddingP(
        name: 'Cohere Embed v4.0',
        desc: 'Cohere multilingual multimodal embedding model',
        multimodal: true,
        modalities: const <AiModelModality>{
          AiModelModality.text,
          AiModelModality.image,
        },
        context: 128000,
        dimensions: 1536,
        maxInputTokens: 128000,
        customDimensions: true,
        endpointPath: 'v2/embed',
        batchSize: 96,
        supportedParameters: _cohereEmbeddingParameters,
        inputTypes: const <String>['search_document', 'search_query', 'image'],
        defaultInputType: 'search_document',
        queryInputType: 'search_query',
        documentInputType: 'search_document',
        taskTypes: const <String>[
          'search_document',
          'search_query',
          'classification',
          'clustering',
        ],
        encodingFormats: const <String>[
          'float',
          'int8',
          'uint8',
          'binary',
          'ubinary',
        ],
        defaultEncodingFormat: 'float',
        defaultTruncation: 'END',
        minDimensions: 256,
        maxDimensions: 1536,
        maxInputsPerBatch: 96,
        supportsTruncation: true,
      );
    }
    if (id.contains('embed-multilingual-light-v3')) {
      return _cohereTextEmbedV3(
        name: 'Cohere Embed Multilingual Light v3.0',
        desc: 'Cohere lightweight multilingual embedding model',
        dimensions: 384,
      );
    }
    if (id.contains('embed-multilingual-v3')) {
      return _cohereTextEmbedV3(
        name: 'Cohere Embed Multilingual v3.0',
        desc: 'Cohere multilingual embedding model',
        dimensions: 1024,
      );
    }
    if (id.contains('embed-english-light-v3')) {
      return _cohereTextEmbedV3(
        name: 'Cohere Embed English Light v3.0',
        desc: 'Cohere lightweight English embedding model',
        dimensions: 384,
      );
    }
    if (id.contains('embed-english-v3')) {
      return _cohereTextEmbedV3(
        name: 'Cohere Embed English v3.0',
        desc: 'Cohere English embedding model',
        dimensions: 1024,
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Voyage AI
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _voyage(String id) {
    if (!id.startsWith('voyage-')) return null;
    final isVoyage4 = id.startsWith('voyage-4');
    final isVoyage35 = id.startsWith('voyage-3.5');
    final isVoyage3Large = id.startsWith('voyage-3-large');
    final isCode = id.startsWith('voyage-code');
    final isFinance = id.startsWith('voyage-finance');
    final isLaw = id.startsWith('voyage-law');
    final isMultimodal = id.startsWith('voyage-multimodal');
    final isLegacyLite =
        id.startsWith('voyage-3-lite') || id.startsWith('voyage-2-lite');
    final supportsFlexibleOutput =
        isVoyage4 || isVoyage35 || isVoyage3Large || isCode;
    final highThroughputBatch =
        id.startsWith('voyage-4-lite') || id.startsWith('voyage-3.5-lite');
    final constrainedBatch =
        id.startsWith('voyage-4-large') ||
        isVoyage3Large ||
        isCode ||
        isFinance ||
        isLaw;
    final maxTokensPerBatch = highThroughputBatch
        ? 1000000
        : constrainedBatch
        ? 120000
        : 320000;
    final code = id.contains('code');
    final lite = isLegacyLite;
    return _embeddingP(
      name: code
          ? 'Voyage Code 3'
          : isFinance
          ? 'Voyage Finance 2'
          : isLaw
          ? 'Voyage Law 2'
          : isMultimodal
          ? 'Voyage Multimodal'
          : id.startsWith('voyage-4')
          ? 'Voyage 4'
          : lite
          ? 'Voyage Lite'
          : 'Voyage Embedding',
      desc: code
          ? 'Voyage code retrieval embedding model'
          : isFinance
          ? 'Voyage finance-domain embedding model'
          : isLaw
          ? 'Voyage legal-domain embedding model'
          : isMultimodal
          ? 'Voyage multimodal embedding model'
          : 'Voyage general-purpose multilingual embedding model',
      multimodal: isMultimodal,
      modalities: isMultimodal
          ? _textImageVideo
          : const <AiModelModality>{AiModelModality.text},
      context: isLaw ? 16000 : 32000,
      dimensions: lite ? 512 : 1024,
      maxInputTokens: isLaw ? 16000 : 32000,
      customDimensions: supportsFlexibleOutput,
      batchSize: 128,
      supportedParameters: _voyageEmbeddingParameters,
      inputTypes: isMultimodal
          ? const <String>['document', 'query', 'image', 'video']
          : const <String>['document', 'query'],
      defaultInputType: 'document',
      queryInputType: 'query',
      documentInputType: 'document',
      taskTypes: const <String>['document', 'query'],
      outputDTypes: supportsFlexibleOutput
          ? const <String>['float', 'int8', 'uint8', 'binary', 'ubinary']
          : const <String>[],
      defaultOutputDType: supportsFlexibleOutput ? 'float' : null,
      defaultTruncation: 'true',
      minDimensions: supportsFlexibleOutput ? 256 : null,
      maxDimensions: supportsFlexibleOutput ? 2048 : null,
      maxTokensPerBatch: maxTokensPerBatch,
      supportsTruncation: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Jina AI
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _jina(String id) {
    if (id.startsWith('jina-embeddings-v5-omni')) {
      final nano = id.contains('nano');
      return _embeddingP(
        name: nano ? 'Jina Embeddings v5 Omni Nano' : 'Jina Embeddings v5 Omni',
        desc: 'Jina multilingual omni embedding model',
        multimodal: true,
        modalities: _allModalities,
        context: nano ? 8192 : 32768,
        dimensions: nano ? 768 : 1024,
        maxInputTokens: nano ? 8192 : 32768,
        customDimensions: true,
        batchSize: 64,
        supportedParameters: _jinaEmbeddingParameters,
        inputTypes: const <String>['text', 'image', 'audio', 'video', 'file'],
        taskTypes: const <String>[
          'retrieval.query',
          'retrieval.passage',
          'text-matching',
          'classification',
          'clustering',
        ],
        defaultTaskType: 'retrieval.passage',
        queryTaskType: 'retrieval.query',
        documentTaskType: 'retrieval.passage',
        encodingFormats: const <String>['float', 'base64', 'binary'],
        defaultEncodingFormat: 'float',
        outputDTypes: const <String>['float', 'binary'],
        defaultOutputDType: 'float',
        outputsNormalized: true,
        minDimensions: 32,
        maxDimensions: nano ? 768 : 1024,
        supportsTruncation: true,
      );
    }
    if (id.startsWith('jina-embeddings-v5-text')) {
      final nano = id.contains('nano');
      return _embeddingP(
        name: nano ? 'Jina Embeddings v5 Text Nano' : 'Jina Embeddings v5 Text',
        desc: 'Jina multilingual text embedding model',
        context: nano ? 8192 : 32768,
        dimensions: nano ? 768 : 1024,
        maxInputTokens: nano ? 8192 : 32768,
        customDimensions: true,
        batchSize: 64,
        supportedParameters: _jinaEmbeddingParameters,
        taskTypes: const <String>[
          'retrieval.query',
          'retrieval.passage',
          'text-matching',
          'classification',
          'clustering',
        ],
        defaultTaskType: 'retrieval.passage',
        queryTaskType: 'retrieval.query',
        documentTaskType: 'retrieval.passage',
        encodingFormats: const <String>['float', 'base64', 'binary'],
        defaultEncodingFormat: 'float',
        outputDTypes: const <String>['float', 'binary'],
        defaultOutputDType: 'float',
        outputsNormalized: true,
        minDimensions: 32,
        maxDimensions: nano ? 768 : 1024,
        supportsTruncation: true,
      );
    }
    if (id.startsWith('jina-embeddings-v4')) {
      return _embeddingP(
        name: 'Jina Embeddings v4',
        desc: 'Jina multimodal multilingual embedding model',
        multimodal: true,
        modalities: const <AiModelModality>{
          AiModelModality.text,
          AiModelModality.image,
        },
        context: 32768,
        dimensions: 2048,
        maxInputTokens: 32768,
        customDimensions: true,
        batchSize: 64,
        supportedParameters: _jinaEmbeddingParameters,
        inputTypes: const <String>['text', 'image'],
        taskTypes: const <String>[
          'retrieval.query',
          'retrieval.passage',
          'text-matching',
          'code',
        ],
        defaultTaskType: 'retrieval.passage',
        queryTaskType: 'retrieval.query',
        documentTaskType: 'retrieval.passage',
        encodingFormats: const <String>['float', 'base64', 'binary'],
        defaultEncodingFormat: 'float',
        outputDTypes: const <String>['float', 'binary'],
        defaultOutputDType: 'float',
        outputsNormalized: true,
        minDimensions: 128,
        maxDimensions: 2048,
        supportsTruncation: true,
      );
    }
    if (id.startsWith('jina-embeddings-v3')) {
      return _embeddingP(
        name: 'Jina Embeddings v3',
        desc: 'Jina multilingual text embedding model',
        context: 8192,
        dimensions: 1024,
        maxInputTokens: 8192,
        customDimensions: true,
        batchSize: 64,
        supportedParameters: _jinaEmbeddingParameters,
        taskTypes: const <String>[
          'retrieval.query',
          'retrieval.passage',
          'text-matching',
          'classification',
          'separation',
        ],
        defaultTaskType: 'retrieval.passage',
        queryTaskType: 'retrieval.query',
        documentTaskType: 'retrieval.passage',
        encodingFormats: const <String>['float', 'base64', 'binary'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
        minDimensions: 32,
        maxDimensions: 1024,
        supportsTruncation: true,
      );
    }
    if (id.startsWith('jina-clip')) {
      return _embeddingP(
        name: 'Jina CLIP',
        desc: 'Jina image/text embedding model',
        multimodal: true,
        modalities: const <AiModelModality>{
          AiModelModality.text,
          AiModelModality.image,
        },
        context: 8192,
        dimensions: 1024,
        maxInputTokens: 8192,
        customDimensions: true,
        batchSize: 64,
        supportedParameters: _jinaEmbeddingParameters,
        inputTypes: const <String>['text', 'image'],
        outputsNormalized: true,
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Open-source / OpenAI-compatible embedding model IDs
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile _openSourceTextEmbeddingP({
    required String name,
    required String desc,
    required int context,
    required int dimensions,
    bool customDimensions = false,
    int? minDimensions,
    int? maxDimensions,
    String? queryModelId,
    String? documentModelId,
    List<String> supportedParameters = _openAiCompatibleEmbeddingParameters,
    List<String> inputTypes = const <String>['text'],
    String? defaultInputType,
    String? queryInputType,
    String? documentInputType,
    List<String> taskTypes = const <String>[],
    String? defaultTaskType,
    String? queryTaskType,
    String? documentTaskType,
    String? queryTextPrefix,
    String? documentTextPrefix,
    List<String> encodingFormats = const <String>['float'],
    String? defaultEncodingFormat = 'float',
    List<String> outputDTypes = const <String>[],
    String? defaultOutputDType,
    String? defaultTruncation,
    int batchSize = 64,
    int? maxInputsPerBatch,
    int? maxTokensPerBatch,
    bool outputsNormalized = true,
  }) {
    return _embeddingP(
      name: name,
      desc: desc,
      context: context,
      dimensions: dimensions,
      maxInputTokens: context,
      customDimensions: customDimensions,
      batchSize: batchSize,
      queryModelId: queryModelId,
      documentModelId: documentModelId,
      supportedParameters: supportedParameters,
      inputTypes: inputTypes,
      defaultInputType: defaultInputType,
      queryInputType: queryInputType,
      documentInputType: documentInputType,
      taskTypes: taskTypes,
      defaultTaskType: defaultTaskType,
      queryTaskType: queryTaskType,
      documentTaskType: documentTaskType,
      queryTextPrefix: queryTextPrefix,
      documentTextPrefix: documentTextPrefix,
      encodingFormats: encodingFormats,
      defaultEncodingFormat: defaultEncodingFormat,
      outputDTypes: outputDTypes,
      defaultOutputDType: defaultOutputDType,
      defaultTruncation: defaultTruncation,
      outputsNormalized: outputsNormalized,
      minDimensions: minDimensions,
      maxDimensions: maxDimensions,
      maxInputsPerBatch: maxInputsPerBatch,
      maxTokensPerBatch: maxTokensPerBatch,
    );
  }

  static AiModelProfile? _openSourceEmbedding(String id) {
    if (id.startsWith('pplx-embed-context-v1')) {
      final large = id.contains('4b');
      final dimensions = large ? 2560 : 1024;
      return _embeddingP(
        name: large
            ? 'Perplexity Contextual Embed v1 4B'
            : 'Perplexity Contextual Embed v1 0.6B',
        desc: 'Perplexity contextualized embedding model',
        context: 32768,
        dimensions: dimensions,
        maxInputTokens: 32768,
        customDimensions: true,
        endpointPath: 'v1/embeddings/contextualized',
        batchSize: 128,
        specialBody: true,
        supportedParameters: _perplexityEmbeddingParameters,
        inputTypes: const <String>['document_chunks'],
        encodingFormats: const <String>['base64_int8', 'base64_binary'],
        defaultEncodingFormat: 'base64_int8',
        outputDTypes: const <String>['int8', 'binary'],
        defaultOutputDType: 'int8',
        minDimensions: 128,
        maxDimensions: dimensions,
        maxInputsPerBatch: 16000,
        maxTokensPerBatch: 120000,
        outputsNormalized: false,
      );
    }
    if (id.startsWith('pplx-embed-v1')) {
      final large = id.contains('4b');
      final dimensions = large ? 2560 : 1024;
      return _openSourceTextEmbeddingP(
        name: large ? 'Perplexity Embed v1 4B' : 'Perplexity Embed v1 0.6B',
        desc: 'Perplexity text embedding model',
        context: 32768,
        dimensions: dimensions,
        customDimensions: true,
        minDimensions: 128,
        maxDimensions: dimensions,
        supportedParameters: _perplexityEmbeddingParameters,
        encodingFormats: const <String>['base64_int8', 'base64_binary'],
        defaultEncodingFormat: 'base64_int8',
        outputDTypes: const <String>['int8', 'binary'],
        defaultOutputDType: 'int8',
        batchSize: 100,
        maxInputsPerBatch: 512,
        maxTokensPerBatch: 120000,
        outputsNormalized: false,
      );
    }
    if (id.contains('titan-embed-text-v2')) {
      return _openSourceTextEmbeddingP(
        name: 'Amazon Titan Text Embeddings V2',
        desc: 'Amazon Bedrock text embedding model',
        context: 8192,
        dimensions: 1024,
        customDimensions: true,
        minDimensions: 256,
        maxDimensions: 1024,
        outputDTypes: const <String>['float', 'binary'],
        defaultOutputDType: 'float',
      );
    }
    if (id.contains('titan-embed-text')) {
      return _openSourceTextEmbeddingP(
        name: 'Amazon Titan Text Embeddings',
        desc: 'Amazon Bedrock text embedding model',
        context: 8192,
        dimensions: 1536,
      );
    }
    if (id.contains('titan-embed-image')) {
      return _embeddingP(
        name: 'Amazon Titan Multimodal Embeddings',
        desc: 'Amazon Bedrock image/text embedding model',
        multimodal: true,
        modalities: const <AiModelModality>{
          AiModelModality.text,
          AiModelModality.image,
        },
        context: 128,
        dimensions: 1024,
        maxInputTokens: 128,
        customDimensions: true,
        batchSize: 16,
        inputTypes: const <String>['text', 'image'],
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
        minDimensions: 256,
        maxDimensions: 1024,
      );
    }
    if (id.contains('nv-embedqa-e5')) {
      return _openSourceTextEmbeddingP(
        name: 'NVIDIA NV-EmbedQA E5',
        desc: 'NVIDIA NIM E5 retrieval embedding model',
        context: 512,
        dimensions: 1024,
        supportedParameters: _typedOpenAiCompatibleEmbeddingParameters,
        inputTypes: const <String>['query', 'passage'],
        defaultInputType: 'passage',
        queryInputType: 'query',
        documentInputType: 'passage',
        taskTypes: const <String>['query', 'passage'],
        defaultTaskType: 'passage',
        queryTaskType: 'query',
        documentTaskType: 'passage',
        queryTextPrefix: 'query:',
        documentTextPrefix: 'passage:',
        defaultTruncation: 'END',
      );
    }
    if (id.contains('nv-embed') || id.contains('nvidia/nv-embed')) {
      return _openSourceTextEmbeddingP(
        name: 'NVIDIA NV-Embed',
        desc: 'NVIDIA retrieval embedding model',
        context: 32768,
        dimensions: 4096,
        customDimensions: true,
        minDimensions: 256,
        maxDimensions: 4096,
        taskTypes: const <String>['query', 'document'],
        defaultTaskType: 'document',
        queryTaskType: 'query',
        documentTaskType: 'document',
      );
    }
    if (id.contains('solar-embedding')) {
      final isQuery = id.contains('query');
      return _openSourceTextEmbeddingP(
        name: 'Solar Embedding',
        desc: 'Upstage Solar text embedding model',
        context: 4096,
        dimensions: 4096,
        batchSize: 100,
        queryModelId: 'solar-embedding-1-large-query',
        documentModelId: 'solar-embedding-1-large-passage',
        taskTypes: const <String>['query', 'passage'],
        defaultTaskType: isQuery ? 'query' : 'passage',
        queryTaskType: 'query',
        documentTaskType: 'passage',
      );
    }
    if (id.contains('slate-125m')) {
      return _openSourceTextEmbeddingP(
        name: 'IBM Slate 125M Embedding',
        desc: 'IBM Granite Slate text embedding model',
        context: 512,
        dimensions: 384,
      );
    }
    if (id.contains('slate-30m')) {
      return _openSourceTextEmbeddingP(
        name: 'IBM Slate 30M Embedding',
        desc: 'IBM Granite Slate text embedding model',
        context: 512,
        dimensions: 384,
      );
    }
    if (id.contains('qwen3-embedding')) {
      final dim = id.contains('8b')
          ? 4096
          : id.contains('4b')
          ? 2560
          : 1024;
      return _openSourceTextEmbeddingP(
        name: 'Qwen3 Embedding',
        desc: 'Qwen3 open-source multilingual embedding model',
        context: 32768,
        dimensions: dim,
        customDimensions: true,
        minDimensions: 32,
        maxDimensions: dim,
      );
    }
    if (id.contains('bge-m3')) {
      return _openSourceTextEmbeddingP(
        name: 'BAAI bge-m3',
        desc: 'BAAI multilingual multi-function embedding model',
        context: 8192,
        dimensions: 1024,
        taskTypes: const <String>['dense', 'sparse', 'multi-vector'],
        defaultTaskType: 'dense',
      );
    }
    if (id.contains('bge-large')) {
      return _openSourceTextEmbeddingP(
        name: id.contains('zh') ? 'BAAI bge-large-zh' : 'BAAI bge-large-en',
        desc: id.contains('zh')
            ? 'BAAI Chinese large text embedding model'
            : 'BAAI English large text embedding model',
        context: 512,
        dimensions: 1024,
      );
    }
    if (id.contains('bge-base')) {
      return _openSourceTextEmbeddingP(
        name: id.contains('zh') ? 'BAAI bge-base-zh' : 'BAAI bge-base-en',
        desc: id.contains('zh')
            ? 'BAAI Chinese base text embedding model'
            : 'BAAI English base text embedding model',
        context: 512,
        dimensions: 768,
      );
    }
    if (id.contains('bge-small')) {
      return _openSourceTextEmbeddingP(
        name: id.contains('zh') ? 'BAAI bge-small-zh' : 'BAAI bge-small-en',
        desc: id.contains('zh')
            ? 'BAAI Chinese small text embedding model'
            : 'BAAI English small text embedding model',
        context: 512,
        dimensions: 384,
      );
    }
    if (id.contains('bce-embedding')) {
      return _openSourceTextEmbeddingP(
        name: 'BCE Embedding',
        desc: 'NetEase Youdao bilingual/chinese embedding model',
        context: 512,
        dimensions: 768,
      );
    }
    if (id.contains('nomic-embed')) {
      return _openSourceTextEmbeddingP(
        name: 'Nomic Embed',
        desc: 'Nomic text embedding model',
        context: 8192,
        dimensions: 768,
        customDimensions: true,
        taskTypes: const <String>['search_document', 'search_query'],
        defaultTaskType: 'search_document',
        queryTaskType: 'search_query',
        documentTaskType: 'search_document',
        queryTextPrefix: 'search_query:',
        documentTextPrefix: 'search_document:',
        minDimensions: 64,
        maxDimensions: 768,
      );
    }
    if (id.contains('multilingual-e5') || id.contains('e5-')) {
      final isSmall = id.contains('small');
      final isBase = id.contains('base');
      return _openSourceTextEmbeddingP(
        name: id.contains('multilingual')
            ? 'intfloat multilingual-e5'
            : 'intfloat e5',
        desc: 'E5 retrieval embedding model',
        context: 512,
        dimensions: isSmall
            ? 384
            : isBase
            ? 768
            : 1024,
        taskTypes: const <String>['query', 'passage'],
        defaultTaskType: 'passage',
        queryTaskType: 'query',
        documentTaskType: 'passage',
        queryTextPrefix: 'query:',
        documentTextPrefix: 'passage:',
      );
    }
    if (id.contains('gte-qwen2')) {
      final dimensions = id.contains('7b')
          ? 3584
          : id.contains('1.5b') || id.contains('1-5b')
          ? 1536
          : 1024;
      return _openSourceTextEmbeddingP(
        name: 'GTE Qwen2 Embedding',
        desc: 'Alibaba GTE Qwen2 instruction embedding model',
        context: 32768,
        dimensions: dimensions,
        customDimensions: true,
        minDimensions: 128,
        maxDimensions: dimensions,
        taskTypes: const <String>['query', 'document'],
        defaultTaskType: 'document',
        queryTaskType: 'query',
        documentTaskType: 'document',
      );
    }
    if (id.contains('gte-large') ||
        id.contains('gte-base') ||
        id.contains('gte-small')) {
      final dimensions = id.contains('small')
          ? 384
          : id.contains('base')
          ? 768
          : 1024;
      final longContext = id.contains('v1.5') || id.contains('v1-5');
      return _openSourceTextEmbeddingP(
        name: id.contains('small')
            ? 'GTE Small'
            : id.contains('base')
            ? 'GTE Base'
            : 'GTE Large',
        desc: 'GTE text embedding model',
        context: longContext ? 8192 : 512,
        dimensions: dimensions,
        taskTypes: const <String>['query', 'document'],
        defaultTaskType: 'document',
        queryTaskType: 'query',
        documentTaskType: 'document',
      );
    }
    if (id.contains('mxbai-embed')) {
      return _openSourceTextEmbeddingP(
        name: 'mxbai-embed-large-v1',
        desc: 'Mixedbread large retrieval embedding model',
        context: 512,
        dimensions: 1024,
        taskTypes: const <String>['query', 'document'],
        defaultTaskType: 'document',
        queryTaskType: 'query',
        documentTaskType: 'document',
      );
    }
    if (id.contains('snowflake-arctic-embed')) {
      final dimensions = id.contains('-s') || id.contains('-xs')
          ? 384
          : id.contains('-m')
          ? 768
          : 1024;
      return _openSourceTextEmbeddingP(
        name: 'Snowflake Arctic Embed',
        desc: 'Snowflake Arctic text embedding model',
        context: id.contains('v2') ? 8192 : 512,
        dimensions: dimensions,
        taskTypes: const <String>['query', 'document'],
        defaultTaskType: 'document',
        queryTaskType: 'query',
        documentTaskType: 'document',
      );
    }
    if (id.contains('all-minilm-l6-v2')) {
      return _openSourceTextEmbeddingP(
        name: 'all-MiniLM-L6-v2',
        desc: 'SentenceTransformers compact text embedding model',
        context: 256,
        dimensions: 384,
      );
    }
    if (id.contains('all-mpnet-base-v2')) {
      return _openSourceTextEmbeddingP(
        name: 'all-mpnet-base-v2',
        desc: 'SentenceTransformers MPNet text embedding model',
        context: 384,
        dimensions: 768,
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Grok (xAI)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _grok(String id) {
    // Grok video is only reachable through OpenAI-compatible gateways such
    // as `chenyme/grok2api`, which exposes `POST /v1/videos` (multipart) for
    // `grok-imagine-video`. xAI's native API has no public video endpoint.
    if (id.startsWith('grok-imagine-video') || id == 'grok-video') {
      return _p(
        name: 'Grok Imagine Video',
        desc: 'Async text/image-to-video via grok2api gateway',
        capabilities: _videoGen,
      );
    }
    if (id.startsWith('grok-2-image') ||
        id.startsWith('grok-image') ||
        id.startsWith('grok-imagine-image') ||
        id == 'grok-imagine') {
      return _p(
        name: 'Grok Image',
        desc: 'Image generation model',
        capabilities: _imageGen,
      );
    }
    if (id.startsWith('grok-3-mini-fast')) {
      return _p(
        name: 'Grok-3 Mini Fast',
        desc: 'Ultra-fast compact reasoning',
        context: 131072,
        output: 16384,
        thinking: 16384,
      );
    }
    if (id.startsWith('grok-3-mini')) {
      return _p(
        name: 'Grok-3 Mini',
        desc: 'Compact reasoning model',
        context: 131072,
        output: 16384,
        thinking: 16384,
      );
    }
    if (id.startsWith('grok-3-fast')) {
      return _p(
        name: 'Grok-3 Fast',
        desc: 'Fast flagship with vision',
        multimodal: true,
        modalities: _textImage,
        context: 131072,
        output: 16384,
      );
    }
    if (id.startsWith('grok-3')) {
      return _p(
        name: 'Grok-3',
        desc: 'Grok 旗舰模型别名，当前通常解析到更新的 Grok 4.3 系列。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 1000000,
        output: 16384,
        inputUsdPer1M: 1.25,
        outputUsdPer1M: 2.50,
        cacheReadUsdPer1M: 0.20,
      );
    }
    if (id.contains('vision')) {
      return _p(
        name: 'Grok-2 Vision',
        desc: 'Image understanding model',
        multimodal: true,
        modalities: _textImage,
        context: 32768,
        output: 4096,
      );
    }
    if (id.startsWith('grok-2-mini')) {
      return _p(
        name: 'Grok-2 Mini',
        desc: 'Compact text model',
        context: 131072,
        output: 4096,
      );
    }
    if (id.startsWith('grok-2')) {
      return _p(
        name: 'Grok-2',
        desc: 'Previous generation model',
        context: 131072,
        output: 4096,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Hunyuan (Tencent / 腾讯混元)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _hunyuan(String id) {
    // ── Embedding ────────────────────────────────────────────────────────
    if (id.contains('embedding') || id.contains('embed')) {
      return _embeddingP(
        name: 'Hunyuan Embedding',
        desc: 'Tencent Hunyuan embedding model',
        context: 8192,
        dimensions: 1024,
        maxInputTokens: 8192,
        batchSize: 64,
        endpointPath: 'v1/embeddings',
      );
    }

    // ── Vision models ────────────────────────────────────────────────────
    if (id.contains('vision-video')) {
      return _p(
        name: 'Hunyuan Vision Video',
        desc: 'Video understanding model',
        multimodal: true,
        modalities: _textImageVideo,
      );
    }
    if (id.contains('t1-vision')) {
      return _p(
        name: 'Hunyuan T1 Vision',
        desc: 'Vision model with deep thinking',
        multimodal: true,
        modalities: _textImage,
      );
    }
    if (id.contains('vision')) {
      return _p(
        name: 'Hunyuan Vision',
        desc: 'Image understanding model',
        multimodal: true,
        modalities: _textImage,
      );
    }

    // ── Thinking models ──────────────────────────────────────────────────
    if (id.contains('t1') || id.contains('think')) {
      return _p(name: 'Hunyuan T1', desc: 'Deep thinking model');
    }

    // ── Text models ──────────────────────────────────────────────────────
    if (id.contains('turbos')) {
      return _p(name: 'Hunyuan TurboS', desc: 'Fast text model');
    }
    if (id.contains('hy3-preview') || id.contains('hy3')) {
      return _p(
        name: 'Hunyuan Hy3 Preview',
        desc: '腾讯混元面向 Agent 工作流的高效文本模型。',
        supportsAttachments: false,
        context: 262144,
        inputUsdPer1M: 0.063,
        outputUsdPer1M: 0.21,
        cacheReadUsdPer1M: 0.021,
      );
    }
    if (id.contains('a13b')) {
      return _p(
        name: 'Hunyuan A13B',
        desc: '腾讯混元高性价比文本推理模型。',
        supportsAttachments: false,
        context: 131072,
        output: 131072,
        inputUsdPer1M: 0.14,
        outputUsdPer1M: 0.57,
      );
    }
    if (id.contains('lite')) {
      return _p(
        name: 'Hunyuan Lite',
        desc: 'Free lightweight model',
        context: 256000,
      );
    }
    if (id.contains('large')) {
      return _p(name: 'Hunyuan Large', desc: 'Large text model');
    }
    if (id.contains('pro')) {
      return _p(name: 'Hunyuan Pro', desc: 'Professional text model');
    }
    if (id.contains('standard')) {
      return _p(name: 'Hunyuan Standard', desc: 'Standard text model');
    }

    // Fallback for any hunyuan model ID
    if (id.startsWith('hunyuan')) {
      return _p(name: 'Hunyuan', desc: 'Tencent Hunyuan model');
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MiniMax
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _minimax(String id) {
    if (id.startsWith('embo-01') ||
        id.startsWith('embo') ||
        id.contains('minimax-embedding')) {
      return _embeddingP(
        name: 'MiniMax embo-01',
        desc: 'MiniMax text embedding model',
        context: 8192,
        dimensions: 1536,
        maxInputTokens: 8192,
        batchSize: 64,
        endpointPath: 'v1/embeddings',
      );
    }
    if (id.contains('image')) {
      return _p(
        name: 'MiniMax Image',
        desc: 'Image generation model',
        capabilities: _imageGen,
      );
    }
    if (id.contains('video')) {
      return _p(
        name: 'MiniMax Video',
        desc: 'Video generation model',
        capabilities: _videoGen,
      );
    }
    if (id.contains('speech') ||
        id.contains('audio') ||
        id.contains('music') ||
        id.startsWith('t2a')) {
      return _p(
        name: 'MiniMax Audio',
        desc: 'Audio generation model',
        capabilities: const <AiModelCapability>{
          AiModelCapability.audioGeneration,
        },
      );
    }
    if (id.contains('m2.7') || id.contains('m2-7')) {
      return _p(
        name: 'MiniMax M2.7',
        desc: 'MiniMax 当前旗舰 Agent / 推理模型。',
        supportsAttachments: false,
        context: 204800,
        output: 131000,
        thinking: 131000,
      );
    }
    if (id.contains('m2.5') || id.contains('m2-5')) {
      return _p(
        name: 'MiniMax M2.5',
        desc: 'Long-context reasoning and coding model',
        context: 196000,
        output: 32768,
        thinking: 32768,
      );
    }
    if (id.contains('m1')) {
      return _p(
        name: 'MiniMax M1',
        desc: 'MiniMax 混合推理模型，支持超长上下文。',
        supportsAttachments: false,
        context: 1000000,
        output: 8000,
        thinking: 80000,
        inputUsdPer1M: 0.40,
        outputUsdPer1M: 2.20,
      );
    }
    if (id.contains('abab')) {
      return _p(
        name: 'MiniMax ABAB',
        desc: 'General-purpose MiniMax chat model',
        context: 245000,
        output: 8000,
      );
    }
    if (id.startsWith('minimax') || id.startsWith('mini-max')) {
      return _p(name: 'MiniMax', desc: 'MiniMax model');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Agnes (Sapiens AI)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _agnes(String id) {
    if (!id.startsWith('agnes-')) return null;

    const chatParameters = <String>[
      'temperature',
      'top_p',
      'max_tokens',
      'frequency_penalty',
      'presence_penalty',
      'repetition_penalty',
      'stop',
      'seed',
      'tools',
      'tool_choice',
      'chat_template_kwargs',
    ];
    const imageParameters = <String>[
      'prompt',
      'size',
      'return_base64',
      'extra_body.image',
      'extra_body.response_format',
    ];
    const videoParameters = <String>[
      'prompt',
      'image',
      'mode',
      'height',
      'width',
      'num_frames',
      'frame_rate',
      'num_inference_steps',
      'seed',
      'negative_prompt',
      'extra_body.image',
      'extra_body.mode',
    ];

    if (id == 'agnes-1.5-flash') {
      return _p(
        name: 'Agnes 1.5 Flash',
        desc: 'Sapiens AI 轻量低延迟多模态聊天模型。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 256000,
        output: 65536,
        inputUsdPer1M: 0,
        outputUsdPer1M: 0,
        supportedParameters: chatParameters,
      );
    }
    if (id == 'agnes-2.0-flash') {
      return _p(
        name: 'Agnes 2.0 Flash',
        desc: 'Sapiens AI 智能体、工具调用、编程、推理和图片理解模型。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 256000,
        output: 65536,
        inputUsdPer1M: 0,
        outputUsdPer1M: 0,
        supportedParameters: chatParameters,
        defaultParameters: const <String, Object?>{
          'chat_template_kwargs': <String, Object?>{'enable_thinking': false},
        },
      );
    }
    if (id == 'agnes-image-2.0-flash') {
      return _p(
        name: 'Agnes Image 2.0 Flash',
        desc: 'Sapiens AI 图像生成、图生图与多图编辑模型。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        inputUsdPer1M: 0,
        outputUsdPer1M: 0,
        supportedParameters: imageParameters,
        capabilities: _imageGen,
      );
    }
    if (id == 'agnes-image-2.1-flash') {
      return _p(
        name: 'Agnes Image 2.1 Flash',
        desc: 'Sapiens AI 高密度图像生成、图生图与多图编辑模型。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        inputUsdPer1M: 0,
        outputUsdPer1M: 0,
        supportedParameters: imageParameters,
        capabilities: _imageGen,
      );
    }
    if (id == 'agnes-video-v2.0') {
      return _p(
        name: 'Agnes Video V2.0',
        desc: 'Sapiens AI 异步文生视频、图生视频与关键帧视频模型。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImageVideo,
        inputUsdPer1M: 0,
        outputUsdPer1M: 0,
        supportedParameters: videoParameters,
        capabilities: _videoGen,
      );
    }
    if (id.startsWith('agnes-image-')) {
      return _p(
        name: 'Agnes Image',
        desc: 'Sapiens AI image generation model',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        supportedParameters: imageParameters,
        capabilities: _imageGen,
      );
    }
    if (id.startsWith('agnes-video-')) {
      return _p(
        name: 'Agnes Video',
        desc: 'Sapiens AI video generation model',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImageVideo,
        supportedParameters: videoParameters,
        capabilities: _videoGen,
      );
    }
    return _p(
      name: 'Agnes',
      desc: 'Sapiens AI OpenAI-compatible model',
      multimodal: true,
      supportsAttachments: true,
      modalities: _textImage,
      context: 256000,
      output: 65536,
      supportedParameters: chatParameters,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LongCat
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _longcat(String id) {
    if (!id.contains('longcat')) return null;
    if (id.contains('vision') || id.contains('-vl') || id.contains('_vl')) {
      return _p(
        name: 'LongCat Vision',
        desc: 'LongCat multimodal model',
        multimodal: true,
        modalities: _textImage,
        context: 128000,
        output: 32768,
      );
    }
    if (id.contains('flash')) {
      return _p(
        name: 'LongCat Flash',
        desc: '美团 LongCat 长上下文聊天模型。',
        supportsAttachments: false,
        context: 256000,
        output: 32768,
      );
    }
    if (id.startsWith('longcat')) {
      return _p(
        name: 'LongCat',
        desc: 'Long-context chat model',
        context: 128000,
        output: 32768,
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // JoyCode / JoyCoder
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _joycode(String id) {
    if (id.contains('joycoder') || id.contains('joycode')) {
      return _p(
        name: id.contains('coder') ? 'JoyCoder' : 'JoyCode',
        desc: 'Coding-focused model for agentic development tasks',
        context: 128000,
        output: 32768,
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Wenxin / ERNIE (Baidu 文心一言)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _wenxin(String id) {
    if (id.contains('qwen3-embedding')) {
      final dimensions = id.contains('8b')
          ? 4096
          : id.contains('4b')
          ? 2560
          : 1024;
      return _embeddingP(
        name: 'Qwen3-Embedding',
        desc: 'Baidu Qianfan hosted Qwen3 embedding model',
        context: 8192,
        dimensions: dimensions,
        maxInputTokens: 8192,
        customDimensions: true,
        batchSize: 16,
        maxInputsPerBatch: 16,
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
        minDimensions: 32,
        maxDimensions: dimensions,
      );
    }
    if (id.contains('tao-8k')) {
      return _embeddingP(
        name: 'tao-8k',
        desc: 'Baidu Qianfan long-context text embedding model',
        context: 8192,
        dimensions: 1024,
        maxInputTokens: 8192,
        batchSize: 1,
        maxInputsPerBatch: 1,
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
      );
    }
    if (id.contains('bge-large-zh') || id.contains('bge-large-en')) {
      return _embeddingP(
        name: id.contains('bge-large-zh') ? 'bge-large-zh' : 'bge-large-en',
        desc: 'Baidu Qianfan hosted BGE embedding model',
        context: 512,
        dimensions: 1024,
        maxInputTokens: 512,
        batchSize: 16,
        maxInputsPerBatch: 16,
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
      );
    }
    if (id == 'embedding-v1' || id.contains('embedding-v1')) {
      return _embeddingP(
        name: 'Embedding-V1',
        desc: 'Baidu Qianfan text embedding model',
        context: 384,
        dimensions: 384,
        maxInputTokens: 384,
        batchSize: 16,
        maxInputsPerBatch: 16,
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
      );
    }
    if (id.contains('embedding')) {
      return _embeddingP(
        name: 'Baidu Embedding',
        desc: 'Baidu Qianfan text embedding model',
        context: 8192,
        dimensions: 1024,
        maxInputTokens: 8192,
        batchSize: 16,
        maxInputsPerBatch: 16,
        encodingFormats: const <String>['float'],
        defaultEncodingFormat: 'float',
        outputsNormalized: true,
      );
    }
    if (id.contains('ernie-vilg') || id.contains('image')) {
      return _p(
        name: 'ERNIE Image',
        desc: 'Baidu image generation model',
        capabilities: _imageGen,
      );
    }
    if (id.contains('ernie-4.5-vl-424b') || id.contains('ernie-4-5-vl-424b')) {
      return _p(
        name: 'ERNIE 4.5 VL 424B A47B',
        desc: '百度文心 4.5 旗舰视觉模型。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 131072,
        output: 16000,
        inputUsdPer1M: 0.42,
        outputUsdPer1M: 1.25,
      );
    }
    if (id.contains('ernie-4.5-vl-28b') || id.contains('ernie-4-5-vl-28b')) {
      return _p(
        name: 'ERNIE 4.5 VL 28B A3B',
        desc: '百度文心 4.5 轻量视觉模型。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 131072,
        output: 8000,
        inputUsdPer1M: 0.14,
        outputUsdPer1M: 0.56,
      );
    }
    if (id.contains('ernie-4.5-vl') ||
        id.contains('ernie-4-5-vl') ||
        id.contains('ernie-vl')) {
      return _p(
        name: 'ERNIE 4.5 VL',
        desc: '百度文心多模态视觉模型。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _textImage,
        context: 131072,
        output: 8192,
      );
    }
    if (id.contains('ernie-x1')) {
      return _p(
        name: 'ERNIE X1',
        desc: 'Baidu deep reasoning model',
        context: 128000,
        output: 32768,
        thinking: 32768,
      );
    }
    if (id.contains('ernie-4.5-300b') || id.contains('ernie-4-5-300b')) {
      return _p(
        name: 'ERNIE 4.5 300B A47B',
        desc: '百度文心 4.5 旗舰文本模型。',
        supportsAttachments: false,
        context: 131072,
        output: 12000,
        inputUsdPer1M: 0.28,
        outputUsdPer1M: 1.10,
      );
    }
    if (id.contains('ernie-4.5-21b') || id.contains('ernie-4-5-21b')) {
      final thinking = id.contains('thinking');
      return _p(
        name: thinking ? 'ERNIE 4.5 21B A3B Thinking' : 'ERNIE 4.5 21B A3B',
        desc: thinking ? '百度文心 4.5 轻量推理文本模型。' : '百度文心 4.5 轻量文本模型。',
        supportsAttachments: false,
        context: 131072,
        output: thinking ? 65536 : 8000,
        thinking: thinking ? 65536 : null,
        inputUsdPer1M: 0.07,
        outputUsdPer1M: 0.28,
      );
    }
    if (id.contains('ernie-4.5') || id.contains('ernie-4-5')) {
      return _p(
        name: 'ERNIE 4.5',
        desc: '百度文心旗舰文本模型。',
        supportsAttachments: false,
        context: 128000,
        output: 32768,
      );
    }
    if (id.contains('ernie-4') || id.contains('ernie-bot-4')) {
      return _p(
        name: 'ERNIE 4.0',
        desc: 'Baidu ERNIE flagship model',
        context: 128000,
        output: 8192,
      );
    }
    if (id.contains('ernie-3.5') || id.contains('ernie-bot')) {
      return _p(
        name: 'ERNIE 3.5',
        desc: 'Baidu ERNIE general-purpose model',
        context: 128000,
        output: 8192,
      );
    }
    if (id.contains('ernie') || id.contains('wenxin')) {
      return _p(name: 'ERNIE', desc: 'Baidu Wenxin / ERNIE model');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Meta AI / Llama
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _meta(String id) {
    if (id.contains('llama-4-scout') || id.contains('llama4-scout')) {
      return _p(
        name: 'Llama 4 Scout',
        desc: 'Meta multimodal long-context model',
        multimodal: true,
        modalities: _textImage,
        context: 10000000,
        output: 8192,
      );
    }
    if (id.contains('llama-4-maverick') || id.contains('llama4-maverick')) {
      return _p(
        name: 'Llama 4 Maverick',
        desc: 'Meta multimodal flagship model',
        multimodal: true,
        modalities: _textImage,
        context: 1000000,
        output: 8192,
      );
    }
    if (id.contains('llama-4') || id.contains('llama4')) {
      return _p(
        name: 'Llama 4',
        desc: 'Meta multimodal model family',
        multimodal: true,
        modalities: _textImage,
        context: 1000000,
        output: 8192,
      );
    }
    if (id.contains('llama-3.2-vision') ||
        id.contains('llama3.2-vision') ||
        id.contains('llama-3-2-vision')) {
      return _p(
        name: 'Llama 3.2 Vision',
        desc: 'Meta image understanding model',
        multimodal: true,
        modalities: _textImage,
        context: 128000,
        output: 8192,
      );
    }
    if (id.contains('llama-3.3') || id.contains('llama3.3')) {
      return _p(
        name: 'Llama 3.3',
        desc: 'Meta text model',
        context: 128000,
        output: 8192,
      );
    }
    if (id.contains('llama-3.1') || id.contains('llama3.1')) {
      return _p(
        name: 'Llama 3.1',
        desc: 'Meta long-context text model',
        context: 128000,
        output: 8192,
      );
    }
    if (id.contains('llama-3') || id.contains('llama3')) {
      return _p(
        name: 'Llama 3',
        desc: 'Meta open model family',
        context: 8192,
        output: 8192,
      );
    }
    if (id.contains('llama') || id.startsWith('meta')) {
      return _p(name: 'Meta AI', desc: 'Meta AI / Llama model');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MiMo (Xiaomi / 小米)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _mimo(String id) {
    if (id.contains('mimo-v2.5-pro')) {
      return _p(
        name: 'MiMo V2.5 Pro',
        desc: '小米旗舰文本 Agent / 推理模型。',
        supportsAttachments: false,
        context: 1048576,
        output: 131072,
        inputUsdPer1M: 0.435,
        outputUsdPer1M: 0.87,
        cacheReadUsdPer1M: 0.0036,
      );
    }
    if (id.contains('mimo-v2.5')) {
      return _p(
        name: 'MiMo V2.5',
        desc: '小米原生全模态模型，支持图像、音频与视频输入。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _allModalities,
        context: 1048576,
        output: 131072,
        inputUsdPer1M: 0.14,
        outputUsdPer1M: 0.28,
        cacheReadUsdPer1M: 0.0028,
      );
    }
    if (id.contains('mimo-v2-omni')) {
      return _p(
        name: 'MiMo V2 Omni',
        desc: '小米前代全模态模型，支持图像、音频与视频输入。',
        multimodal: true,
        supportsAttachments: true,
        modalities: _allModalities,
        context: 262144,
        output: 65536,
        inputUsdPer1M: 0.40,
        outputUsdPer1M: 2.00,
        cacheReadUsdPer1M: 0.08,
      );
    }
    if (id.contains('mimo-v2-pro')) {
      return _p(
        name: 'MiMo V2 Pro',
        desc: '小米大参数长上下文文本模型。',
        supportsAttachments: false,
        context: 1048576,
        output: 131072,
        inputUsdPer1M: 1.00,
        outputUsdPer1M: 3.00,
        cacheReadUsdPer1M: 0.20,
      );
    }
    if (id.contains('mimo-v2-flash')) {
      return _p(
        name: 'MiMo V2 Flash',
        desc: '小米高速文本模型。',
        supportsAttachments: false,
        context: 262144,
        output: 65536,
        inputUsdPer1M: 0.10,
        outputUsdPer1M: 0.30,
        cacheReadUsdPer1M: 0.01,
      );
    }
    if (id.startsWith('mimo') || id.startsWith('mi-')) {
      return _p(name: 'MiMo', desc: '小米推理模型');
    }
    return null;
  }
}
