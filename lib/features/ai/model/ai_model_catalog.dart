import 'ai_model_config.dart';

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

    // Protocol-specific lookup.
    final result = switch (protocolType) {
      AiProtocolType.openai   => _openai(id),
      AiProtocolType.claude   => _claude(id),
      AiProtocolType.gemini   => _gemini(id),
      AiProtocolType.deepseek => _deepseek(id),
      AiProtocolType.qwen     => _qwen(id),
      AiProtocolType.glm      => _glm(id),
      AiProtocolType.kimi     => _kimi(id),
      AiProtocolType.seed     => _seed(id),
      AiProtocolType.stepfun  => _stepfun(id),
      AiProtocolType.grok     => _grok(id),
      AiProtocolType.hunyuan  => _hunyuan(id),
      AiProtocolType.mimo     => _mimo(id),
      // Local inference frameworks serve arbitrary open-source models.
      AiProtocolType.ollama ||
      AiProtocolType.vllm ||
      AiProtocolType.sglang   => null,
    };
    if (result != null) return result;

    // Cross-protocol fallback: try all providers for well-known model-ID
    // patterns.  Handles cases like DeepSeek models served via Aliyun/Qwen,
    // or GLM models accessed through OpenAI-compatible endpoints.
    return _openai(id) ?? _claude(id) ?? _gemini(id) ?? _deepseek(id) ??
        _qwen(id) ?? _glm(id) ?? _kimi(id) ?? _seed(id) ??
        _stepfun(id) ?? _grok(id) ?? _hunyuan(id);
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

  /// Shorthand [AiModelProfile] builder for catalog entries.
  static AiModelProfile _p({
    required String name,
    String? desc,
    bool multimodal = false,
    Set<AiModelModality> modalities = const <AiModelModality>{
      AiModelModality.text,
    },
    int? context,
    int? output,
    int? thinking,
    Set<AiModelCapability> capabilities = const <AiModelCapability>{},
  }) {
    return AiModelProfile(
      displayName: name,
      description: desc,
      isMultimodal: multimodal,
      supportedModalities: modalities,
      maxContextLength: context,
      maxOutputLength: output,
      maxThinkingLength: thinking,
      capabilities: capabilities,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OpenAI
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _openai(String id) {
    // ── Image generation ─────────────────────────────────────────────────
    if (id.startsWith('gpt-image') || id.startsWith('dall-e')) {
      return _p(
        name: id.startsWith('dall-e') ? 'DALL·E 3' : 'GPT Image',
        desc: 'Image generation model',
        capabilities: _imageGen,
      );
    }

    // ── Reasoning (o-series) — most specific first ───────────────────────
    if (id.startsWith('o4-mini')) {
      return _p(
        name: 'o4-mini',
        desc: 'Efficient reasoning with vision',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 100000,
        thinking: 100000,
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
        desc: 'Advanced reasoning with vision',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 100000,
        thinking: 100000,
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

    // ── GPT-5.4 series ───────────────────────────────────────────────────
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
        desc: 'Flagship with 1M context and vision',
        multimodal: true,
        modalities: _textImage,
        context: 1000000,
        output: 32768,
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
        desc: 'High-performance with extended thinking',
        multimodal: true,
        modalities: _textImage,
        context: 200000,
        output: 64000,
        thinking: 128000,
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
    // ── Gemini 2.5 ───────────────────────────────────────────────────────
    if (id.startsWith('gemini-2.5-pro')) {
      return _p(
        name: 'Gemini 2.5 Pro',
        desc: 'Most capable Gemini with full multimodal and thinking',
        multimodal: true,
        modalities: _allModalities,
        context: 1048576,
        output: 65536,
        thinking: 65536,
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
        desc: 'Fast multimodal with thinking',
        multimodal: true,
        modalities: _allModalities,
        context: 1048576,
        output: 65536,
        thinking: 65536,
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
        desc: 'Deep thinking model',
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
    // ── Image generation ─────────────────────────────────────────────────
    if (id.startsWith('qwen-image') || id.startsWith('wan')) {
      return _p(
        name: id.startsWith('wan') ? 'Wanxiang' : 'Qwen Image',
        desc: 'Image generation',
        capabilities: _imageGen,
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
        modalities: <AiModelModality>{AiModelModality.text, AiModelModality.audio},
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
        desc: 'Flagship model for complex tasks',
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
        desc: 'Multimodal: text, image, video input',
        multimodal: true,
        modalities: _textImageVideo,
        context: 1000000,
        output: 65536,
        thinking: 81920,
      );
    }
    if (id.startsWith('qwen-plus')) {
      return _p(
        name: 'Qwen-Plus',
        desc: 'Balanced text model with thinking',
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
        desc: 'Speed-optimized text model',
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
    if (id.startsWith('qwen3-32b') || id.startsWith('qwen3-30b') ||
        id.startsWith('qwen3-14b') || id.startsWith('qwen3-8b') ||
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
    // ── Image / Video generation ─────────────────────────────────────────
    if (id.startsWith('cogview')) {
      return _p(name: 'CogView', desc: 'Image generation', capabilities: _imageGen);
    }
    if (id.startsWith('cogvideo')) {
      return _p(name: 'CogVideoX', desc: 'Video generation', capabilities: _videoGen);
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
        desc: 'Vision understanding model',
        multimodal: true,
        modalities: _textImage,
        context: 128000,
        output: 32000,
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
        desc: 'Latest flagship with deep thinking',
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
        desc: 'Flagship model',
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
        desc: 'Cost-effective model',
        context: 128000,
        output: 96000,
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
    if (id.contains('kimi-k2.5') || id.contains('kimi-k2-5')) {
      return _p(
        name: 'Kimi K2.5',
        desc: 'Flagship reasoning model',
        context: 262144,
        output: 98304,
        thinking: 81920,
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
    // ── Image generation ─────────────────────────────────────────────────
    if (id.contains('seedream')) {
      return _p(name: 'Seedream', desc: 'Image generation', capabilities: _imageGen);
    }

    // ── Video generation ─────────────────────────────────────────────────
    if (id.contains('seedance')) {
      return _p(name: 'Seedance', desc: 'Video generation', capabilities: _videoGen);
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
        desc: 'Multimodal agent model',
        multimodal: true,
        modalities: _textImage,
        context: 256000,
        output: 32000,
        thinking: 32000,
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
        desc: 'Text generation model',
        context: 128000,
        output: 16000,
      );
    }

    // ── Embedding ────────────────────────────────────────────────────────
    if (id.contains('embedding')) {
      return _p(
        name: 'Doubao Embedding',
        desc: 'Text/multimodal embedding model',
        context: 128000,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // StepFun (阶跃星辰)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _stepfun(String id) {
    // ── Vision models (check before text) ────────────────────────────────
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
    if (id.startsWith('step-2')) {
      return _p(
        name: 'Step-2',
        desc: 'Flagship text model',
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
  // Grok (xAI)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _grok(String id) {
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
        desc: 'Flagship with vision and reasoning',
        multimodal: true,
        modalities: _textImage,
        context: 131072,
        output: 16384,
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
    if (id.contains('a13b')) {
      return _p(name: 'Hunyuan A13B', desc: 'Efficient text model');
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
  // MiMo (Xiaomi / 小米)
  // ═══════════════════════════════════════════════════════════════════════════

  static AiModelProfile? _mimo(String id) {
    if (id.startsWith('mimo') || id.startsWith('mi-')) {
      return _p(name: 'MiMo', desc: 'Xiaomi reasoning model');
    }
    return null;
  }
}
