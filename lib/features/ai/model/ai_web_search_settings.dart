import '../../../shared/util/input_value_parsing.dart';
import 'ai_web_engine_resilience.dart';

/// 受支持的搜索引擎种类。顺序与默认渲染顺序一致；用户可在设置中拖拽改变实际优先级。
enum AiWebSearchEngineKind {
  /// Tavily Search API — 专业 AI 搜索；需要 `TAVILY_API_KEY`。
  tavily,

  /// Exa（formerly Metaphor）— 神经搜索；需要 `EXA_API_KEY`。
  exa,

  /// Moonshot Kimi 联网搜索（`/v1/tools/web_search` 兼容协议）。
  kimi,

  /// 百度 AI 搜索 API（千帆 / `aip.baidubce.com/...`）。
  baidu,

  /// Linkup Web Search（`https://api.linkup.so/v1/search`）。
  linkup,

  /// 博查（Bocha）AI 搜索（`https://api.bochaai.com/v1/web-search`）。
  bocha,

  /// DuckDuckGo HTML 抓取（无需 key，结果质量较低，作为兜底）。
  duckduckgo,

  /// xAI Grok Live Search（`messages` body 的 `search_parameters`）。
  grok,

  /// Google Gemini Grounding Search（`tools.googleSearch`）。
  gemini,

  /// Bing HTML 抓取（无需 key，作为最终兜底）。
  bing,

  /// SearXNG / Startpage 兼容元搜索实例（用户自填 endpoint）。
  searxng;

  /// 是否需要 API key 才能使用。
  bool get requiresApiKey {
    return switch (this) {
      AiWebSearchEngineKind.duckduckgo => false,
      AiWebSearchEngineKind.bing => false,
      AiWebSearchEngineKind.searxng => false,
      _ => true,
    };
  }

  /// 是否为兜底引擎（即使用户全禁也会启用）。
  bool get isFallback {
    return this == AiWebSearchEngineKind.bing ||
        this == AiWebSearchEngineKind.duckduckgo ||
        this == AiWebSearchEngineKind.searxng;
  }
}

/// summary 详细程度档位。
enum AiWebSearchSummaryDetail {
  /// 简明扼要：≤ 200 字。
  brief,

  /// 中规中矩：200–600 字。
  balanced,

  /// 全面详细：600–1500 字。
  comprehensive,

  /// 细致入微：1500+ 字，多段落带引用。
  exhaustive,
}

/// summary 语言风格档位。
enum AiWebSearchSummaryStyle {
  /// 中性百科风（默认）。
  neutral,

  /// 技术分析风（结构化、含术语）。
  technical,

  /// 通俗轻松风。
  casual,

  /// 严格结构化（要点列表 + 来源段）。
  structured,
}

/// summary 子代理使用的模型策略。
enum AiWebSearchModelMode {
  /// 自动跟随当前会话模型（默认）。
  followSession,

  /// 固定使用指定 provider/model。
  fixed,
}

/// 单个搜索引擎的配置。
class AiWebSearchEngineConfig {
  const AiWebSearchEngineConfig({
    required this.kind,
    this.enabled = false,
    this.weight = defaultWeight,
    this.maxRetries = defaultMaxRetries,
    this.truncationChars = defaultTruncationChars,
    this.apiKey,
    this.providerConfigId,
    this.endpointOverride,
  });

  static const int defaultWeight = AiWebEngineConfigPolicy.defaultWeight;
  static const int minWeight = AiWebEngineConfigPolicy.minWeight;
  static const int maxWeight = AiWebEngineConfigPolicy.maxWeight;
  static const int defaultMaxRetries =
      AiWebEngineConfigPolicy.defaultMaxRetries;
  static const int maxRetriesUpperBound = AiWebEngineExecutionPolicy.maxRetries;

  /// 默认截断阈值（字符数）。用户层面以「tokens」标注，按 ~4 字符 / token 估算
  /// 即 20000 tokens ≈ 80000 字符；为保守起见取 80000。
  static const int defaultTruncationChars = 80000;
  static const int minTruncationChars =
      AiWebEngineConfigPolicy.minTruncationChars;
  static const int maxTruncationChars =
      AiWebEngineConfigPolicy.maxTruncationChars;
  static const IntValueRange _weightRange = AiWebEngineConfigPolicy.weightRange;
  static const IntValueRange _maxRetriesRange =
      AiWebEngineConfigPolicy.maxRetriesRange;
  static const IntValueRange _truncationCharsRange = IntValueRange(
    fallback: defaultTruncationChars,
    min: minTruncationChars,
    max: maxTruncationChars,
  );

  final AiWebSearchEngineKind kind;
  final bool enabled;
  final int weight;
  final int maxRetries;
  final int truncationChars;

  /// 用户直接粘贴的 API key（明文，与 `AiServiceProvider` apiKey 体系并行存在）。
  final String? apiKey;

  /// 关联到某个 `AiModelConfig.id`，复用该 provider 的 apiKey；优先级高于 [apiKey]。
  /// 仅对 kimi / grok / gemini 等与已注册 provider 重叠的引擎有意义。
  final String? providerConfigId;

  /// 自定义 endpoint（仅对 searxng 等需要用户提供实例 URL 的引擎有意义）。
  final String? endpointOverride;

  AiWebSearchEngineConfig copyWith({
    bool? enabled,
    int? weight,
    int? maxRetries,
    int? truncationChars,
    String? apiKey,
    String? providerConfigId,
    String? endpointOverride,
    bool clearApiKey = false,
    bool clearProviderConfigId = false,
    bool clearEndpointOverride = false,
  }) {
    return AiWebSearchEngineConfig(
      kind: kind,
      enabled: enabled ?? this.enabled,
      weight: weight ?? this.weight,
      maxRetries: maxRetries ?? this.maxRetries,
      truncationChars: truncationChars ?? this.truncationChars,
      apiKey: clearApiKey ? null : (apiKey ?? this.apiKey),
      providerConfigId: clearProviderConfigId
          ? null
          : (providerConfigId ?? this.providerConfigId),
      endpointOverride: clearEndpointOverride
          ? null
          : (endpointOverride ?? this.endpointOverride),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'kind': kind.name,
      'enabled': enabled,
      'weight': weight,
      'max_retries': maxRetries,
      'truncation_chars': truncationChars,
    };
    putIfNotBlank(json, 'api_key', apiKey);
    putIfNotBlank(json, 'provider_config_id', providerConfigId);
    putIfNotBlank(json, 'endpoint_override', endpointOverride);
    return json;
  }

  static AiWebSearchEngineConfig? fromJson(Map<String, Object?> json) {
    final rawKind = stringFromValue(json['kind']);
    final kind = enumByName(AiWebSearchEngineKind.values, rawKind);
    if (kind == null) return null;
    return AiWebSearchEngineConfig(
      kind: kind,
      enabled: boolFromValue(json['enabled']),
      weight: _weightRange.fromValue(json['weight']),
      maxRetries: _maxRetriesRange.fromValue(json['max_retries']),
      truncationChars: _truncationCharsRange.fromValue(
        json['truncation_chars'],
      ),
      apiKey: optionalStringFromValue(json['api_key']),
      providerConfigId: optionalStringFromValue(json['provider_config_id']),
      endpointOverride: optionalStringFromValue(json['endpoint_override']),
    );
  }
}

/// WebSearch 内建工具的全部 sub-agent / 数据源 / summary 配置。
class AiWebSearchSettings {
  const AiWebSearchSettings({
    required this.engines,
    this.resultCount = defaultResultCount,
    this.modelMode = AiWebSearchModelMode.followSession,
    this.fixedModelProviderConfigId,
    this.fixedModelId,
    this.parallel = true,
    this.parallelWorkers = AiWebEngineExecutionPolicy.defaultParallelWorkers,
    this.summaryDetail = AiWebSearchSummaryDetail.balanced,
    this.summaryStyle = AiWebSearchSummaryStyle.neutral,
    this.summaryMinChars = 0,
    this.summaryMaxChars = defaultSummaryMaxChars,
    this.cacheTtlSeconds = defaultCacheTtlSeconds,
    this.cacheMaxBytes = AiWebEngineCachePolicy.defaultMaxBytes,
    this.resilience = AiWebEngineResilienceSettings.defaults,
  });

  /// 默认配置：所有引擎按 [AiWebSearchEngineKind] 顺序枚举出来，全部禁用。
  /// 当用户全部禁用时，运行期会自动启用 `bing` / `duckduckgo` 兜底。
  factory AiWebSearchSettings.defaults() {
    return AiWebSearchSettings(
      engines: [
        for (final kind in AiWebSearchEngineKind.values)
          AiWebSearchEngineConfig(kind: kind),
      ],
    );
  }

  static const int defaultResultCount = 8;
  static const int minResultCount = 1;
  static const int maxResultCount = 30;

  static const int defaultSummaryMaxChars = 1500;
  static const int maxSummaryMaxChars = 8000;

  /// 关键词 → summary 元数据的本地缓存默认 TTL（秒）。0 表示停用缓存；
  /// 上下限见 [AiWebEngineCachePolicy]。
  static const int defaultCacheTtlSeconds = 300;

  static const IntValueRange _resultCountRange = IntValueRange(
    fallback: defaultResultCount,
    min: minResultCount,
    max: maxResultCount,
  );
  static const IntValueRange _summaryMinCharsRange = IntValueRange(
    fallback: 0,
    min: 0,
    max: maxSummaryMaxChars,
  );
  static const IntValueRange _summaryMaxCharsRange = IntValueRange(
    fallback: defaultSummaryMaxChars,
    min: 0,
    max: maxSummaryMaxChars,
  );
  static const IntValueRange _cacheTtlSecondsRange = IntValueRange(
    fallback: defaultCacheTtlSeconds,
    min: AiWebEngineCachePolicy.minTtlSeconds,
    max: AiWebEngineCachePolicy.maxTtlSeconds,
  );
  final List<AiWebSearchEngineConfig> engines;
  final int resultCount;
  final AiWebSearchModelMode modelMode;
  final String? fixedModelProviderConfigId;
  final String? fixedModelId;
  final bool parallel;
  final int parallelWorkers;
  final AiWebSearchSummaryDetail summaryDetail;
  final AiWebSearchSummaryStyle summaryStyle;
  final int summaryMinChars;
  final int summaryMaxChars;

  /// 缓存命中有效期（秒）。0 = 关闭。
  final int cacheTtlSeconds;

  /// 缓存目录磁盘占用上限（字节，含 metadata + summary 内容）。
  final int cacheMaxBytes;

  final AiWebEngineResilienceSettings resilience;

  bool get cacheEnabled => cacheTtlSeconds > 0;

  /// 把 [engines] 中已启用的部分按当前顺序返回。
  List<AiWebSearchEngineConfig> enabledEnginesInOrder() =>
      engines.where((e) => e.enabled).toList(growable: false);

  AiWebSearchSettings copyWith({
    List<AiWebSearchEngineConfig>? engines,
    int? resultCount,
    AiWebSearchModelMode? modelMode,
    String? fixedModelProviderConfigId,
    String? fixedModelId,
    bool? parallel,
    int? parallelWorkers,
    AiWebSearchSummaryDetail? summaryDetail,
    AiWebSearchSummaryStyle? summaryStyle,
    int? summaryMinChars,
    int? summaryMaxChars,
    int? cacheTtlSeconds,
    int? cacheMaxBytes,
    AiWebEngineResilienceSettings? resilience,
    bool clearFixedModel = false,
  }) {
    return AiWebSearchSettings(
      engines: engines ?? this.engines,
      resultCount: resultCount ?? this.resultCount,
      modelMode: modelMode ?? this.modelMode,
      fixedModelProviderConfigId: clearFixedModel
          ? null
          : (fixedModelProviderConfigId ?? this.fixedModelProviderConfigId),
      fixedModelId: clearFixedModel
          ? null
          : (fixedModelId ?? this.fixedModelId),
      parallel: parallel ?? this.parallel,
      parallelWorkers: parallelWorkers ?? this.parallelWorkers,
      summaryDetail: summaryDetail ?? this.summaryDetail,
      summaryStyle: summaryStyle ?? this.summaryStyle,
      summaryMinChars: summaryMinChars ?? this.summaryMinChars,
      summaryMaxChars: summaryMaxChars ?? this.summaryMaxChars,
      cacheTtlSeconds: cacheTtlSeconds ?? this.cacheTtlSeconds,
      cacheMaxBytes: cacheMaxBytes ?? this.cacheMaxBytes,
      resilience: resilience ?? this.resilience,
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'engines': engines.map((e) => e.toJson()).toList(growable: false),
      'result_count': resultCount,
      'model_mode': modelMode.name,
      if (fixedModelProviderConfigId != null)
        'fixed_model_provider_config_id': fixedModelProviderConfigId,
      if (fixedModelId != null) 'fixed_model_id': fixedModelId,
      'parallel': parallel,
      'parallel_workers': parallelWorkers,
      'summary_detail': summaryDetail.name,
      'summary_style': summaryStyle.name,
      'summary_min_chars': summaryMinChars,
      'summary_max_chars': summaryMaxChars,
      'cache_ttl_seconds': cacheTtlSeconds,
      'cache_max_bytes': cacheMaxBytes,
    };
    resilience.writeJsonTo(json);
    return json;
  }

  static AiWebSearchSettings? fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return null;

    final engines = decodeOrderedAiWebEngineConfigs(
      raw: json['engines'],
      kinds: AiWebSearchEngineKind.values,
      decode: AiWebSearchEngineConfig.fromJson,
      kindOf: (config) => config.kind,
      createDefault: (kind) => AiWebSearchEngineConfig(kind: kind),
    );

    final modelMode = enumByNameOr(
      AiWebSearchModelMode.values,
      json['model_mode'],
      fallback: AiWebSearchModelMode.followSession,
    );
    final summaryDetail = enumByNameOr(
      AiWebSearchSummaryDetail.values,
      json['summary_detail'],
      fallback: AiWebSearchSummaryDetail.balanced,
    );
    final summaryStyle = enumByNameOr(
      AiWebSearchSummaryStyle.values,
      json['summary_style'],
      fallback: AiWebSearchSummaryStyle.neutral,
    );
    final summaryMaxChars = _summaryMaxCharsRange.fromValue(
      json['summary_max_chars'],
    );
    final parsedSummaryMinChars = _summaryMinCharsRange.fromValue(
      json['summary_min_chars'],
    );
    final summaryMinChars = parsedSummaryMinChars > summaryMaxChars
        ? summaryMaxChars
        : parsedSummaryMinChars;
    final resilience = AiWebEngineResilienceSettings.fromJson(json);

    return AiWebSearchSettings(
      engines: engines,
      resultCount: _resultCountRange.fromValue(json['result_count']),
      modelMode: modelMode,
      fixedModelProviderConfigId: optionalStringFromValue(
        json['fixed_model_provider_config_id'],
      ),
      fixedModelId: optionalStringFromValue(json['fixed_model_id']),
      parallel: boolFromValue(json['parallel'], defaultValue: true),
      parallelWorkers: AiWebEngineExecutionPolicy.parallelWorkersRange
          .fromValue(json['parallel_workers']),
      summaryDetail: summaryDetail,
      summaryStyle: summaryStyle,
      summaryMinChars: summaryMinChars,
      summaryMaxChars: summaryMaxChars,
      cacheTtlSeconds: _cacheTtlSecondsRange.fromValue(
        json['cache_ttl_seconds'],
      ),
      cacheMaxBytes: AiWebEngineCachePolicy.maxBytesRange.fromValue(
        optionalPositiveIntFromValue(json['cache_max_bytes']),
      ),
      resilience: resilience,
    );
  }
}
