import '../../../shared/util/input_value_parsing.dart';
import 'ai_web_engine_resilience.dart';

/// 受支持的 WebFetch 数据源种类。和 WebSearch 平行——很多源既能搜也能抓
/// （firecrawl / tavily-extract / exa-contents 是真正的 URL 抓取，
/// 其它引擎在 URL→内容场景下会以 URL 作为 query 走它们的搜索 API
/// 取最相关 hit 的 content/snippet）。
enum AiWebFetchEngineKind {
  /// Firecrawl `/v1/scrape` —— 专业 URL 抓取，需要 `FC_API_KEY`。
  firecrawl,

  /// Scrapling 本地 Python 抓取桥接。
  scrapling,

  /// Jina Reader `r.jina.ai` —— URL → Markdown，无需 API Key。
  jina,

  /// Tavily `/extract` —— URL → 全文。
  tavily,

  /// Exa `/contents` —— URL 列表 → 全文（含正文/HL）。
  exa,

  /// Moonshot Kimi `web_search` 工具，URL 作为 query。
  kimi,

  /// 百度 AI 搜索 API，URL 作为 query。
  baidu,

  /// Linkup Search，URL 作为 query。
  linkup,

  /// Bocha Search，URL 作为 query。
  bocha,

  /// DuckDuckGo HTML 抓取（无需 key，URL 作为 query），兜底。
  duckduckgo,

  /// xAI Grok Live Search citations（URL 作为 query）。
  grok,

  /// Google Gemini Grounding（URL 作为 query）。
  gemini,

  /// Bing HTML 抓取（无需 key），兜底。
  bing;

  bool get requiresApiKey {
    return switch (this) {
      AiWebFetchEngineKind.scrapling => false,
      AiWebFetchEngineKind.jina => false,
      AiWebFetchEngineKind.duckduckgo => false,
      AiWebFetchEngineKind.bing => false,
      _ => true,
    };
  }

  /// 失败兜底引擎（即使用户全禁也会启用）。
  bool get isFallback {
    return this == AiWebFetchEngineKind.bing ||
        this == AiWebFetchEngineKind.duckduckgo;
  }
}

/// 单个数据源的用户配置。
class AiWebFetchEngineConfig {
  const AiWebFetchEngineConfig({
    required this.kind,
    this.enabled = false,
    this.weight = defaultWeight,
    this.maxRetries = defaultMaxRetries,
    this.truncationChars = defaultTruncationChars,
    this.connectionTimeoutSeconds = defaultConnectionTimeoutSeconds,
    this.responseTimeoutSeconds = defaultResponseTimeoutSeconds,
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

  /// 用户层标注「tokens」，按 ~4 字符 / token 估算 → 25000 tokens ≈ 100000 字符。
  static const int defaultTruncationChars = 100000;
  static const int minTruncationChars =
      AiWebEngineConfigPolicy.minTruncationChars;
  static const int maxTruncationChars =
      AiWebEngineConfigPolicy.maxTruncationChars;
  static const int defaultConnectionTimeoutSeconds = 10;
  static const int minConnectionTimeoutSeconds = 1;
  static const int maxConnectionTimeoutSeconds = 120;
  static const int defaultResponseTimeoutSeconds = 30;
  static const int minResponseTimeoutSeconds = 5;
  static const int maxResponseTimeoutSeconds = 300;
  static const IntValueRange _weightRange = AiWebEngineConfigPolicy.weightRange;
  static const IntValueRange _maxRetriesRange =
      AiWebEngineConfigPolicy.maxRetriesRange;
  static const IntValueRange _truncationCharsRange = IntValueRange(
    fallback: defaultTruncationChars,
    min: minTruncationChars,
    max: maxTruncationChars,
  );
  static const IntValueRange _connectionTimeoutSecondsRange = IntValueRange(
    fallback: defaultConnectionTimeoutSeconds,
    min: minConnectionTimeoutSeconds,
    max: maxConnectionTimeoutSeconds,
  );
  static const IntValueRange _responseTimeoutSecondsRange = IntValueRange(
    fallback: defaultResponseTimeoutSeconds,
    min: minResponseTimeoutSeconds,
    max: maxResponseTimeoutSeconds,
  );

  final AiWebFetchEngineKind kind;
  final bool enabled;
  final int weight;
  final int maxRetries;
  final int truncationChars;
  final int connectionTimeoutSeconds;
  final int responseTimeoutSeconds;
  final String? apiKey;
  final String? providerConfigId;
  final String? endpointOverride;

  AiWebFetchEngineConfig copyWith({
    bool? enabled,
    int? weight,
    int? maxRetries,
    int? truncationChars,
    int? connectionTimeoutSeconds,
    int? responseTimeoutSeconds,
    String? apiKey,
    String? providerConfigId,
    String? endpointOverride,
    bool clearApiKey = false,
    bool clearProviderConfigId = false,
    bool clearEndpointOverride = false,
  }) {
    return AiWebFetchEngineConfig(
      kind: kind,
      enabled: enabled ?? this.enabled,
      weight: weight ?? this.weight,
      maxRetries: maxRetries ?? this.maxRetries,
      truncationChars: truncationChars ?? this.truncationChars,
      connectionTimeoutSeconds:
          connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      responseTimeoutSeconds:
          responseTimeoutSeconds ?? this.responseTimeoutSeconds,
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
      'connection_timeout_seconds': connectionTimeoutSeconds,
      'response_timeout_seconds': responseTimeoutSeconds,
    };
    putIfNotBlank(json, 'api_key', apiKey);
    putIfNotBlank(json, 'provider_config_id', providerConfigId);
    putIfNotBlank(json, 'endpoint_override', endpointOverride);
    return json;
  }

  static AiWebFetchEngineConfig? fromJson(Map<String, Object?> json) {
    final rawKind = stringFromValue(json['kind']);
    final kind = enumByName(AiWebFetchEngineKind.values, rawKind);
    if (kind == null) return null;
    return AiWebFetchEngineConfig(
      kind: kind,
      enabled: boolFromValue(json['enabled']),
      weight: _weightRange.fromValue(json['weight']),
      maxRetries: _maxRetriesRange.fromValue(json['max_retries']),
      truncationChars: _truncationCharsRange.fromValue(
        json['truncation_chars'],
      ),
      connectionTimeoutSeconds: _connectionTimeoutSecondsRange.fromValue(
        json['connection_timeout_seconds'],
      ),
      responseTimeoutSeconds: _responseTimeoutSecondsRange.fromValue(
        json['response_timeout_seconds'],
      ),
      apiKey: optionalStringFromValue(json['api_key']),
      providerConfigId: optionalStringFromValue(json['provider_config_id']),
      endpointOverride: optionalStringFromValue(json['endpoint_override']),
    );
  }
}

/// WebFetch 内建工具的全部数据源 / 调度 / 缓存配置。
///
/// 设计上与 [AiWebSearchSettings] 保持平行：相同的引擎卡片 UI、相同的
/// 排序权重 fan-out 模型、相同的缓存语义；仅去掉 summary 模型字段
/// （WebFetch 直接把原始内容塞给 model 让 model 现场总结）。
class AiWebFetchScraplingSettings {
  const AiWebFetchScraplingSettings({
    this.pythonExecutable,
    this.startupTimeoutSeconds = defaultStartupTimeoutSeconds,
    this.requestTimeoutSeconds = defaultRequestTimeoutSeconds,
    this.installTimeoutSeconds = defaultInstallTimeoutSeconds,
  });

  static const int defaultStartupTimeoutSeconds = 12;
  static const int minStartupTimeoutSeconds = 3;
  static const int maxStartupTimeoutSeconds = 120;
  static const int defaultRequestTimeoutSeconds = 30;
  static const int minRequestTimeoutSeconds = 5;
  static const int maxRequestTimeoutSeconds = 180;
  static const int defaultInstallTimeoutSeconds = 300;
  static const int minInstallTimeoutSeconds = 30;
  static const int maxInstallTimeoutSeconds = 1800;
  static const IntValueRange _startupTimeoutSecondsRange = IntValueRange(
    fallback: defaultStartupTimeoutSeconds,
    min: minStartupTimeoutSeconds,
    max: maxStartupTimeoutSeconds,
  );
  static const IntValueRange _requestTimeoutSecondsRange = IntValueRange(
    fallback: defaultRequestTimeoutSeconds,
    min: minRequestTimeoutSeconds,
    max: maxRequestTimeoutSeconds,
  );
  static const IntValueRange _installTimeoutSecondsRange = IntValueRange(
    fallback: defaultInstallTimeoutSeconds,
    min: minInstallTimeoutSeconds,
    max: maxInstallTimeoutSeconds,
  );

  final String? pythonExecutable;
  final int startupTimeoutSeconds;
  final int requestTimeoutSeconds;
  final int installTimeoutSeconds;

  AiWebFetchScraplingSettings copyWith({
    String? pythonExecutable,
    int? startupTimeoutSeconds,
    int? requestTimeoutSeconds,
    int? installTimeoutSeconds,
    bool clearPythonExecutable = false,
  }) {
    return AiWebFetchScraplingSettings(
      pythonExecutable: clearPythonExecutable
          ? null
          : (pythonExecutable ?? this.pythonExecutable),
      startupTimeoutSeconds:
          startupTimeoutSeconds ?? this.startupTimeoutSeconds,
      requestTimeoutSeconds:
          requestTimeoutSeconds ?? this.requestTimeoutSeconds,
      installTimeoutSeconds:
          installTimeoutSeconds ?? this.installTimeoutSeconds,
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'startup_timeout_seconds': startupTimeoutSeconds,
      'request_timeout_seconds': requestTimeoutSeconds,
      'install_timeout_seconds': installTimeoutSeconds,
    };
    putIfNotBlank(json, 'python_executable', pythonExecutable);
    return json;
  }

  static AiWebFetchScraplingSettings? fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return null;
    return AiWebFetchScraplingSettings(
      pythonExecutable: optionalStringFromValue(json['python_executable']),
      startupTimeoutSeconds: _startupTimeoutSecondsRange.fromValue(
        json['startup_timeout_seconds'],
      ),
      requestTimeoutSeconds: _requestTimeoutSecondsRange.fromValue(
        json['request_timeout_seconds'],
      ),
      installTimeoutSeconds: _installTimeoutSecondsRange.fromValue(
        json['install_timeout_seconds'],
      ),
    );
  }
}

class AiWebFetchSettings {
  const AiWebFetchSettings({
    required this.engines,
    this.resultCount = defaultResultCount,
    this.parallel = true,
    this.parallelWorkers = AiWebEngineExecutionPolicy.defaultParallelWorkers,
    this.cacheTtlSeconds = defaultCacheTtlSeconds,
    this.cacheMaxBytes = AiWebEngineCachePolicy.defaultMaxBytes,
    this.resilience = AiWebEngineResilienceSettings.defaults,
    this.scrapling = const AiWebFetchScraplingSettings(),
  });

  /// 默认配置：所有引擎按枚举顺序排列、全部禁用；运行时自动启用 bing+ddg 兜底。
  factory AiWebFetchSettings.defaults() {
    return AiWebFetchSettings(
      engines: [
        for (final kind in AiWebFetchEngineKind.values)
          AiWebFetchEngineConfig(kind: kind),
      ],
    );
  }

  static const int defaultResultCount = 8;
  static const int minResultCount = 1;
  static const int maxResultCount = 30;

  /// URL → 内容缓存默认 TTL（秒）。15 分钟；上下限见 [AiWebEngineCachePolicy]。
  static const int defaultCacheTtlSeconds = 15 * 60;

  static const IntValueRange _resultCountRange = IntValueRange(
    fallback: defaultResultCount,
    min: minResultCount,
    max: maxResultCount,
  );
  static const IntValueRange _cacheTtlSecondsRange = IntValueRange(
    fallback: defaultCacheTtlSeconds,
    min: AiWebEngineCachePolicy.minTtlSeconds,
    max: AiWebEngineCachePolicy.maxTtlSeconds,
  );
  final List<AiWebFetchEngineConfig> engines;
  final int resultCount;
  final bool parallel;
  final int parallelWorkers;
  final int cacheTtlSeconds;
  final int cacheMaxBytes;
  final AiWebEngineResilienceSettings resilience;
  final AiWebFetchScraplingSettings scrapling;

  bool get cacheEnabled => cacheTtlSeconds > 0;

  List<AiWebFetchEngineConfig> enabledEnginesInOrder() =>
      engines.where((e) => e.enabled).toList(growable: false);

  AiWebFetchSettings copyWith({
    List<AiWebFetchEngineConfig>? engines,
    int? resultCount,
    bool? parallel,
    int? parallelWorkers,
    int? cacheTtlSeconds,
    int? cacheMaxBytes,
    AiWebEngineResilienceSettings? resilience,
    AiWebFetchScraplingSettings? scrapling,
  }) {
    return AiWebFetchSettings(
      engines: engines ?? this.engines,
      resultCount: resultCount ?? this.resultCount,
      parallel: parallel ?? this.parallel,
      parallelWorkers: parallelWorkers ?? this.parallelWorkers,
      cacheTtlSeconds: cacheTtlSeconds ?? this.cacheTtlSeconds,
      cacheMaxBytes: cacheMaxBytes ?? this.cacheMaxBytes,
      resilience: resilience ?? this.resilience,
      scrapling: scrapling ?? this.scrapling,
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'engines': engines.map((e) => e.toJson()).toList(growable: false),
      'result_count': resultCount,
      'parallel': parallel,
      'parallel_workers': parallelWorkers,
      'cache_ttl_seconds': cacheTtlSeconds,
      'cache_max_bytes': cacheMaxBytes,
    };
    resilience.writeJsonTo(json);
    json['scrapling'] = scrapling.toJson();
    return json;
  }

  static AiWebFetchSettings? fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return null;

    final engines = decodeOrderedAiWebEngineConfigs(
      raw: json['engines'],
      kinds: AiWebFetchEngineKind.values,
      decode: AiWebFetchEngineConfig.fromJson,
      kindOf: (config) => config.kind,
      createDefault: (kind) => AiWebFetchEngineConfig(kind: kind),
    );
    final resilience = AiWebEngineResilienceSettings.fromJson(json);

    return AiWebFetchSettings(
      engines: engines,
      scrapling:
          AiWebFetchScraplingSettings.fromJson(json['scrapling']) ??
          const AiWebFetchScraplingSettings(),
      resultCount: _resultCountRange.fromValue(json['result_count']),
      parallel: boolFromValue(json['parallel'], defaultValue: true),
      parallelWorkers: AiWebEngineExecutionPolicy.parallelWorkersRange
          .fromValue(json['parallel_workers']),
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
