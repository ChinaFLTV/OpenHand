import 'dart:convert';

import '../../../app/support/silent_log.dart';

/// 受支持的 WebFetch 数据源种类。和 WebSearch 平行——很多源既能搜也能抓
/// （firecrawl / tavily-extract / exa-contents 是真正的 URL 抓取，
/// 其它引擎在 URL→内容场景下会以 URL 作为 query 走它们的搜索 API
/// 取最相关 hit 的 content/snippet）。
enum AiWebFetchEngineKind {
  /// Firecrawl `/v1/scrape` —— 专业 URL 抓取，需要 `FC_API_KEY`。
  firecrawl,

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
    this.apiKey,
    this.providerConfigId,
    this.endpointOverride,
  });

  static const int defaultWeight = 50;
  static const int minWeight = 1;
  static const int maxWeight = 100;
  static const int defaultMaxRetries = 3;
  static const int maxRetriesUpperBound = 10;

  /// 用户层标注「tokens」，按 ~4 字符 / token 估算 → 25000 tokens ≈ 100000 字符。
  static const int defaultTruncationChars = 100000;
  static const int minTruncationChars = 1000;
  static const int maxTruncationChars = 400000;

  final AiWebFetchEngineKind kind;
  final bool enabled;
  final int weight;
  final int maxRetries;
  final int truncationChars;
  final String? apiKey;
  final String? providerConfigId;
  final String? endpointOverride;

  AiWebFetchEngineConfig copyWith({
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
    return AiWebFetchEngineConfig(
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
    return <String, Object?>{
      'kind': kind.name,
      'enabled': enabled,
      'weight': weight,
      'max_retries': maxRetries,
      'truncation_chars': truncationChars,
      if (apiKey != null && apiKey!.isNotEmpty) 'api_key': apiKey,
      if (providerConfigId != null && providerConfigId!.isNotEmpty)
        'provider_config_id': providerConfigId,
      if (endpointOverride != null && endpointOverride!.isNotEmpty)
        'endpoint_override': endpointOverride,
    };
  }

  static AiWebFetchEngineConfig? fromJson(Map<String, Object?> json) {
    final rawKind = '${json['kind'] ?? ''}'.trim();
    final kind = AiWebFetchEngineKind.values
        .where((e) => e.name == rawKind)
        .firstOrNull;
    if (kind == null) return null;
    int clamp(int value, int lo, int hi) =>
        value < lo ? lo : (value > hi ? hi : value);
    return AiWebFetchEngineConfig(
      kind: kind,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
      weight: clamp(
        (json['weight'] as num?)?.toInt() ?? defaultWeight,
        minWeight,
        maxWeight,
      ),
      maxRetries: clamp(
        (json['max_retries'] as num?)?.toInt() ?? defaultMaxRetries,
        0,
        maxRetriesUpperBound,
      ),
      truncationChars: clamp(
        (json['truncation_chars'] as num?)?.toInt() ?? defaultTruncationChars,
        minTruncationChars,
        maxTruncationChars,
      ),
      apiKey: json['api_key'] is String ? json['api_key'] as String : null,
      providerConfigId: json['provider_config_id'] is String
          ? json['provider_config_id'] as String
          : null,
      endpointOverride: json['endpoint_override'] is String
          ? json['endpoint_override'] as String
          : null,
    );
  }
}

/// WebFetch 内建工具的全部数据源 / 调度 / 缓存配置。
///
/// 设计上与 [AiWebSearchSettings] 保持平行：相同的引擎卡片 UI、相同的
/// 排序权重 fan-out 模型、相同的缓存语义；仅去掉 summary 模型字段
/// （WebFetch 直接把原始内容塞给 model 让 model 现场总结）。
class AiWebFetchSettings {
  const AiWebFetchSettings({
    required this.engines,
    this.resultCount = defaultResultCount,
    this.parallel = true,
    this.parallelWorkers = defaultParallelWorkers,
    this.cacheTtlSeconds = defaultCacheTtlSeconds,
    this.cacheMaxBytes = defaultCacheMaxBytes,
  });

  static const int defaultResultCount = 8;
  static const int minResultCount = 1;
  static const int maxResultCount = 30;

  static const int defaultParallelWorkers = 3;
  static const int minParallelWorkers = 1;
  static const int maxParallelWorkers = 9;

  /// URL → 内容缓存默认 TTL（秒）。15 分钟。
  static const int defaultCacheTtlSeconds = 15 * 60;
  static const int minCacheTtlSeconds = 0;
  static const int maxCacheTtlSeconds = 60 * 60 * 24 * 7;

  /// 缓存目录磁盘占用上限（字节）。默认 50 MB；0 = 无上限。
  static const int defaultCacheMaxBytes = 50 * 1024 * 1024;
  static const int minCacheMaxBytes = 0;
  static const int maxCacheMaxBytes = 2 * 1024 * 1024 * 1024;

  final List<AiWebFetchEngineConfig> engines;
  final int resultCount;
  final bool parallel;
  final int parallelWorkers;
  final int cacheTtlSeconds;
  final int cacheMaxBytes;

  bool get cacheEnabled => cacheTtlSeconds > 0;

  /// 默认配置：所有引擎按枚举顺序排列、全部禁用；运行时自动启用 bing+ddg 兜底。
  // ignore: sort_constructors_first
  factory AiWebFetchSettings.defaults() {
    return AiWebFetchSettings(
      engines: [
        for (final kind in AiWebFetchEngineKind.values)
          AiWebFetchEngineConfig(kind: kind),
      ],
    );
  }

  List<AiWebFetchEngineConfig> enabledEnginesInOrder() =>
      engines.where((e) => e.enabled).toList(growable: false);

  AiWebFetchSettings copyWith({
    List<AiWebFetchEngineConfig>? engines,
    int? resultCount,
    bool? parallel,
    int? parallelWorkers,
    int? cacheTtlSeconds,
    int? cacheMaxBytes,
  }) {
    return AiWebFetchSettings(
      engines: engines ?? this.engines,
      resultCount: resultCount ?? this.resultCount,
      parallel: parallel ?? this.parallel,
      parallelWorkers: parallelWorkers ?? this.parallelWorkers,
      cacheTtlSeconds: cacheTtlSeconds ?? this.cacheTtlSeconds,
      cacheMaxBytes: cacheMaxBytes ?? this.cacheMaxBytes,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'engines': engines.map((e) => e.toJson()).toList(growable: false),
      'result_count': resultCount,
      'parallel': parallel,
      'parallel_workers': parallelWorkers,
      'cache_ttl_seconds': cacheTtlSeconds,
      'cache_max_bytes': cacheMaxBytes,
    };
  }

  static AiWebFetchSettings? fromJson(Object? raw) {
    Map<String, Object?>? json;
    if (raw is Map) {
      json = Map<String, Object?>.from(raw);
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          json = Map<String, Object?>.from(decoded);
        }
      } catch (error, stack) {
        silentLog('ai_web_fetch_settings', 'decode JSON string', error, stack);
        return null;
      }
    }
    if (json == null) return null;

    final rawEngines = json['engines'];
    final engines = <AiWebFetchEngineConfig>[];
    final seenKinds = <AiWebFetchEngineKind>{};
    if (rawEngines is List) {
      for (final entry in rawEngines) {
        if (entry is Map) {
          final cfg = AiWebFetchEngineConfig.fromJson(
            Map<String, Object?>.from(entry),
          );
          if (cfg != null && seenKinds.add(cfg.kind)) engines.add(cfg);
        }
      }
    }
    for (final kind in AiWebFetchEngineKind.values) {
      if (!seenKinds.contains(kind)) {
        engines.add(AiWebFetchEngineConfig(kind: kind));
      }
    }

    int clamp(int value, int lo, int hi) =>
        value < lo ? lo : (value > hi ? hi : value);

    return AiWebFetchSettings(
      engines: engines,
      resultCount: clamp(
        (json['result_count'] as num?)?.toInt() ?? defaultResultCount,
        minResultCount,
        maxResultCount,
      ),
      parallel: json['parallel'] is bool ? json['parallel'] as bool : true,
      parallelWorkers: clamp(
        (json['parallel_workers'] as num?)?.toInt() ?? defaultParallelWorkers,
        minParallelWorkers,
        maxParallelWorkers,
      ),
      cacheTtlSeconds: clamp(
        (json['cache_ttl_seconds'] as num?)?.toInt() ?? defaultCacheTtlSeconds,
        minCacheTtlSeconds,
        maxCacheTtlSeconds,
      ),
      cacheMaxBytes: clamp(
        (json['cache_max_bytes'] as num?)?.toInt() ?? defaultCacheMaxBytes,
        minCacheMaxBytes,
        maxCacheMaxBytes,
      ),
    );
  }
}
