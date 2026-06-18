import 'dart:convert';

import '../../../app/support/silent_log.dart';
import '../../../shared/util/byte_size_format.dart';

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

  static const int defaultWeight = 50;
  static const int minWeight = 1;
  static const int maxWeight = 100;
  static const int defaultMaxRetries = 3;
  static const int maxRetriesUpperBound = 10;

  /// 默认截断阈值（字符数）。用户层面以「tokens」标注，按 ~4 字符 / token 估算
  /// 即 20000 tokens ≈ 80000 字符；为保守起见取 80000。
  static const int defaultTruncationChars = 80000;
  static const int minTruncationChars = 1000;
  static const int maxTruncationChars = 400000;

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

  static AiWebSearchEngineConfig? fromJson(Map<String, Object?> json) {
    final rawKind = '${json['kind'] ?? ''}'.trim();
    final kind = AiWebSearchEngineKind.values
        .where((e) => e.name == rawKind)
        .firstOrNull;
    if (kind == null) return null;
    int clamp(int value, int lo, int hi) =>
        value < lo ? lo : (value > hi ? hi : value);
    return AiWebSearchEngineConfig(
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

/// WebSearch 内建工具的全部 sub-agent / 数据源 / summary 配置。
class AiWebSearchSettings {
  const AiWebSearchSettings({
    required this.engines,
    this.resultCount = defaultResultCount,
    this.modelMode = AiWebSearchModelMode.followSession,
    this.fixedModelProviderConfigId,
    this.fixedModelId,
    this.parallel = true,
    this.parallelWorkers = defaultParallelWorkers,
    this.summaryDetail = AiWebSearchSummaryDetail.balanced,
    this.summaryStyle = AiWebSearchSummaryStyle.neutral,
    this.summaryMinChars = 0,
    this.summaryMaxChars = defaultSummaryMaxChars,
    this.cacheTtlSeconds = defaultCacheTtlSeconds,
    this.cacheMaxBytes = defaultCacheMaxBytes,
    this.cooldownTier1Failures = defaultCooldownTier1Failures,
    this.cooldownTier1Seconds = defaultCooldownTier1Seconds,
    this.cooldownTier2Failures = defaultCooldownTier2Failures,
    this.cooldownTier2Seconds = defaultCooldownTier2Seconds,
    this.cooldownTier3Failures = defaultCooldownTier3Failures,
    this.cooldownTier3Seconds = defaultCooldownTier3Seconds,
    this.cooldownQuotaSeconds = defaultCooldownQuotaSeconds,
    this.alertSuccessRatePct = 0,
    this.alertAvgDurationMs = 0,
    this.throttlePerMinute = 0,
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

  static const int defaultParallelWorkers = 3;
  static const int minParallelWorkers = 1;
  static const int maxParallelWorkers = 9;

  static const int defaultSummaryMaxChars = 1500;
  static const int maxSummaryMaxChars = 8000;

  /// 关键词 → summary 元数据的本地缓存默认 TTL（秒）。0 表示停用缓存。
  static const int defaultCacheTtlSeconds = 300;
  static const int minCacheTtlSeconds = 0;
  static const int maxCacheTtlSeconds = 60 * 60 * 24 * 7;

  /// 缓存容量上限（字节）。默认 50 MB；0 表示无上限（不推荐）。
  static const int defaultCacheMaxBytes = 50 * kBytesPerMiB;
  static const int minCacheMaxBytes = 0;
  static const int maxCacheMaxBytes = 2 * kBytesPerGiB;

  // ===== 失败自动降级（cooldown）阈值，三档可调。=====
  static const int defaultCooldownTier1Failures = 3;
  static const int defaultCooldownTier1Seconds = 60;
  static const int defaultCooldownTier2Failures = 5;
  static const int defaultCooldownTier2Seconds = 300;
  static const int defaultCooldownTier3Failures = 7;
  static const int defaultCooldownTier3Seconds = 900;
  static const int defaultCooldownQuotaSeconds = 300;
  static const int minCooldownFailures = 2;
  static const int maxCooldownFailures = 50;
  static const int minCooldownSeconds = 5;
  static const int maxCooldownSeconds = 24 * 60 * 60;

  // ===== 告警阈值。0 = 关闭。=====
  static const int maxAlertSuccessRatePct = 100;
  static const int maxAlertAvgDurationMs = 600 * 1000; // 10 min

  // ===== 每引擎每分钟节流上限。0 = 不限。=====
  static const int maxThrottlePerMinute = 600;

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

  /// 失败自动降级 (cooldown) 三档阈值与时长（秒）。
  final int cooldownTier1Failures;
  final int cooldownTier1Seconds;
  final int cooldownTier2Failures;
  final int cooldownTier2Seconds;
  final int cooldownTier3Failures;
  final int cooldownTier3Seconds;

  /// 显式 quota / 429 / rate-limit 错误的固定 cooldown 时长（秒）。
  final int cooldownQuotaSeconds;

  /// 单引擎成功率低于此百分比触发告警。0 = 关闭。
  final int alertSuccessRatePct;

  /// 单引擎平均耗时高于此毫秒触发告警。0 = 关闭。
  final int alertAvgDurationMs;

  /// 单引擎 60 秒内最多调用次数。0 = 不限制。
  final int throttlePerMinute;

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
    int? cooldownTier1Failures,
    int? cooldownTier1Seconds,
    int? cooldownTier2Failures,
    int? cooldownTier2Seconds,
    int? cooldownTier3Failures,
    int? cooldownTier3Seconds,
    int? cooldownQuotaSeconds,
    int? alertSuccessRatePct,
    int? alertAvgDurationMs,
    int? throttlePerMinute,
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
      cooldownTier1Failures:
          cooldownTier1Failures ?? this.cooldownTier1Failures,
      cooldownTier1Seconds: cooldownTier1Seconds ?? this.cooldownTier1Seconds,
      cooldownTier2Failures:
          cooldownTier2Failures ?? this.cooldownTier2Failures,
      cooldownTier2Seconds: cooldownTier2Seconds ?? this.cooldownTier2Seconds,
      cooldownTier3Failures:
          cooldownTier3Failures ?? this.cooldownTier3Failures,
      cooldownTier3Seconds: cooldownTier3Seconds ?? this.cooldownTier3Seconds,
      cooldownQuotaSeconds: cooldownQuotaSeconds ?? this.cooldownQuotaSeconds,
      alertSuccessRatePct: alertSuccessRatePct ?? this.alertSuccessRatePct,
      alertAvgDurationMs: alertAvgDurationMs ?? this.alertAvgDurationMs,
      throttlePerMinute: throttlePerMinute ?? this.throttlePerMinute,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
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
      'cooldown_tier1_failures': cooldownTier1Failures,
      'cooldown_tier1_seconds': cooldownTier1Seconds,
      'cooldown_tier2_failures': cooldownTier2Failures,
      'cooldown_tier2_seconds': cooldownTier2Seconds,
      'cooldown_tier3_failures': cooldownTier3Failures,
      'cooldown_tier3_seconds': cooldownTier3Seconds,
      'cooldown_quota_seconds': cooldownQuotaSeconds,
      'alert_success_rate_pct': alertSuccessRatePct,
      'alert_avg_duration_ms': alertAvgDurationMs,
      'throttle_per_minute': throttlePerMinute,
    };
  }

  static AiWebSearchSettings? fromJson(Object? raw) {
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
        silentLog('ai_web_search_settings', 'decode JSON string', error, stack);
        return null;
      }
    }
    if (json == null) return null;

    final rawEngines = json['engines'];
    final engines = <AiWebSearchEngineConfig>[];
    final seenKinds = <AiWebSearchEngineKind>{};
    if (rawEngines is List) {
      for (final entry in rawEngines) {
        if (entry is Map) {
          final cfg = AiWebSearchEngineConfig.fromJson(
            Map<String, Object?>.from(entry),
          );
          if (cfg != null && seenKinds.add(cfg.kind)) engines.add(cfg);
        }
      }
    }
    // 补齐缺失的 kind（默认禁用），保留用户保存的顺序。
    for (final kind in AiWebSearchEngineKind.values) {
      if (!seenKinds.contains(kind)) {
        engines.add(AiWebSearchEngineConfig(kind: kind));
      }
    }

    final rawModelMode = '${json['model_mode'] ?? ''}'.trim();
    final modelMode =
        AiWebSearchModelMode.values
            .where((m) => m.name == rawModelMode)
            .firstOrNull ??
        AiWebSearchModelMode.followSession;

    final rawDetail = '${json['summary_detail'] ?? ''}'.trim();
    final summaryDetail =
        AiWebSearchSummaryDetail.values
            .where((d) => d.name == rawDetail)
            .firstOrNull ??
        AiWebSearchSummaryDetail.balanced;

    final rawStyle = '${json['summary_style'] ?? ''}'.trim();
    final summaryStyle =
        AiWebSearchSummaryStyle.values
            .where((s) => s.name == rawStyle)
            .firstOrNull ??
        AiWebSearchSummaryStyle.neutral;

    int clamp(int value, int lo, int hi) =>
        value < lo ? lo : (value > hi ? hi : value);

    return AiWebSearchSettings(
      engines: engines,
      resultCount: clamp(
        (json['result_count'] as num?)?.toInt() ?? defaultResultCount,
        minResultCount,
        maxResultCount,
      ),
      modelMode: modelMode,
      fixedModelProviderConfigId:
          json['fixed_model_provider_config_id'] is String
          ? json['fixed_model_provider_config_id'] as String
          : null,
      fixedModelId: json['fixed_model_id'] is String
          ? json['fixed_model_id'] as String
          : null,
      parallel: json['parallel'] is bool ? json['parallel'] as bool : true,
      parallelWorkers: clamp(
        (json['parallel_workers'] as num?)?.toInt() ?? defaultParallelWorkers,
        minParallelWorkers,
        maxParallelWorkers,
      ),
      summaryDetail: summaryDetail,
      summaryStyle: summaryStyle,
      summaryMinChars: clamp(
        (json['summary_min_chars'] as num?)?.toInt() ?? 0,
        0,
        maxSummaryMaxChars,
      ),
      summaryMaxChars: clamp(
        (json['summary_max_chars'] as num?)?.toInt() ?? defaultSummaryMaxChars,
        0,
        maxSummaryMaxChars,
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
      cooldownTier1Failures: clamp(
        (json['cooldown_tier1_failures'] as num?)?.toInt() ??
            defaultCooldownTier1Failures,
        minCooldownFailures,
        maxCooldownFailures,
      ),
      cooldownTier1Seconds: clamp(
        (json['cooldown_tier1_seconds'] as num?)?.toInt() ??
            defaultCooldownTier1Seconds,
        minCooldownSeconds,
        maxCooldownSeconds,
      ),
      cooldownTier2Failures: clamp(
        (json['cooldown_tier2_failures'] as num?)?.toInt() ??
            defaultCooldownTier2Failures,
        minCooldownFailures,
        maxCooldownFailures,
      ),
      cooldownTier2Seconds: clamp(
        (json['cooldown_tier2_seconds'] as num?)?.toInt() ??
            defaultCooldownTier2Seconds,
        minCooldownSeconds,
        maxCooldownSeconds,
      ),
      cooldownTier3Failures: clamp(
        (json['cooldown_tier3_failures'] as num?)?.toInt() ??
            defaultCooldownTier3Failures,
        minCooldownFailures,
        maxCooldownFailures,
      ),
      cooldownTier3Seconds: clamp(
        (json['cooldown_tier3_seconds'] as num?)?.toInt() ??
            defaultCooldownTier3Seconds,
        minCooldownSeconds,
        maxCooldownSeconds,
      ),
      cooldownQuotaSeconds: clamp(
        (json['cooldown_quota_seconds'] as num?)?.toInt() ??
            defaultCooldownQuotaSeconds,
        minCooldownSeconds,
        maxCooldownSeconds,
      ),
      alertSuccessRatePct: clamp(
        (json['alert_success_rate_pct'] as num?)?.toInt() ?? 0,
        0,
        maxAlertSuccessRatePct,
      ),
      alertAvgDurationMs: clamp(
        (json['alert_avg_duration_ms'] as num?)?.toInt() ?? 0,
        0,
        maxAlertAvgDurationMs,
      ),
      throttlePerMinute: clamp(
        (json['throttle_per_minute'] as num?)?.toInt() ?? 0,
        0,
        maxThrottlePerMinute,
      ),
    );
  }
}
