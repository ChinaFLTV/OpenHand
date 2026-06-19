import 'dart:convert';

import '../../../app/support/silent_log.dart';
import '../../../shared/util/input_value_parsing.dart';

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

  static const int defaultWeight = 50;
  static const int minWeight = 1;
  static const int maxWeight = 100;
  static const int defaultMaxRetries = 3;
  static const int maxRetriesUpperBound = 10;

  /// 用户层标注「tokens」，按 ~4 字符 / token 估算 → 25000 tokens ≈ 100000 字符。
  static const int defaultTruncationChars = 100000;
  static const int minTruncationChars = 1000;
  static const int maxTruncationChars = 400000;
  static const int defaultConnectionTimeoutSeconds = 10;
  static const int minConnectionTimeoutSeconds = 1;
  static const int maxConnectionTimeoutSeconds = 120;
  static const int defaultResponseTimeoutSeconds = 30;
  static const int minResponseTimeoutSeconds = 5;
  static const int maxResponseTimeoutSeconds = 300;

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
    return <String, Object?>{
      'kind': kind.name,
      'enabled': enabled,
      'weight': weight,
      'max_retries': maxRetries,
      'truncation_chars': truncationChars,
      'connection_timeout_seconds': connectionTimeoutSeconds,
      'response_timeout_seconds': responseTimeoutSeconds,
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
    return AiWebFetchEngineConfig(
      kind: kind,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
      weight: clampedIntFromValue(
        json['weight'],
        fallback: defaultWeight,
        min: minWeight,
        max: maxWeight,
      ),
      maxRetries: clampedIntFromValue(
        json['max_retries'],
        fallback: defaultMaxRetries,
        min: 0,
        max: maxRetriesUpperBound,
      ),
      truncationChars: clampedIntFromValue(
        json['truncation_chars'],
        fallback: defaultTruncationChars,
        min: minTruncationChars,
        max: maxTruncationChars,
      ),
      connectionTimeoutSeconds: clampedIntFromValue(
        json['connection_timeout_seconds'],
        fallback: defaultConnectionTimeoutSeconds,
        min: minConnectionTimeoutSeconds,
        max: maxConnectionTimeoutSeconds,
      ),
      responseTimeoutSeconds: clampedIntFromValue(
        json['response_timeout_seconds'],
        fallback: defaultResponseTimeoutSeconds,
        min: minResponseTimeoutSeconds,
        max: maxResponseTimeoutSeconds,
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
    return <String, Object?>{
      if (pythonExecutable != null && pythonExecutable!.trim().isNotEmpty)
        'python_executable': pythonExecutable,
      'startup_timeout_seconds': startupTimeoutSeconds,
      'request_timeout_seconds': requestTimeoutSeconds,
      'install_timeout_seconds': installTimeoutSeconds,
    };
  }

  static AiWebFetchScraplingSettings? fromJson(Object? raw) {
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
        silentLog(
          'ai_web_fetch_scrapling_settings',
          'decode JSON string',
          error,
          stack,
        );
        return null;
      }
    }
    if (json == null) return null;
    return AiWebFetchScraplingSettings(
      pythonExecutable: json['python_executable'] is String
          ? json['python_executable'] as String
          : null,
      startupTimeoutSeconds: clampedIntFromValue(
        json['startup_timeout_seconds'],
        fallback: defaultStartupTimeoutSeconds,
        min: minStartupTimeoutSeconds,
        max: maxStartupTimeoutSeconds,
      ),
      requestTimeoutSeconds: clampedIntFromValue(
        json['request_timeout_seconds'],
        fallback: defaultRequestTimeoutSeconds,
        min: minRequestTimeoutSeconds,
        max: maxRequestTimeoutSeconds,
      ),
      installTimeoutSeconds: clampedIntFromValue(
        json['install_timeout_seconds'],
        fallback: defaultInstallTimeoutSeconds,
        min: minInstallTimeoutSeconds,
        max: maxInstallTimeoutSeconds,
      ),
    );
  }
}

class AiWebFetchSettings {
  const AiWebFetchSettings({
    required this.engines,
    this.resultCount = defaultResultCount,
    this.parallel = true,
    this.parallelWorkers = defaultParallelWorkers,
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
  static const int maxAlertAvgDurationMs = 600 * 1000;

  // ===== 每引擎每分钟节流上限。0 = 不限。=====
  static const int maxThrottlePerMinute = 600;

  final List<AiWebFetchEngineConfig> engines;
  final int resultCount;
  final bool parallel;
  final int parallelWorkers;
  final int cacheTtlSeconds;
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
    AiWebFetchScraplingSettings? scrapling,
  }) {
    return AiWebFetchSettings(
      engines: engines ?? this.engines,
      resultCount: resultCount ?? this.resultCount,
      parallel: parallel ?? this.parallel,
      parallelWorkers: parallelWorkers ?? this.parallelWorkers,
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
      scrapling: scrapling ?? this.scrapling,
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
      'scrapling': scrapling.toJson(),
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

    return AiWebFetchSettings(
      engines: engines,
      scrapling:
          AiWebFetchScraplingSettings.fromJson(json['scrapling']) ??
          const AiWebFetchScraplingSettings(),
      resultCount: clampedIntFromValue(
        json['result_count'],
        fallback: defaultResultCount,
        min: minResultCount,
        max: maxResultCount,
      ),
      parallel: json['parallel'] is bool ? json['parallel'] as bool : true,
      parallelWorkers: clampedIntFromValue(
        json['parallel_workers'],
        fallback: defaultParallelWorkers,
        min: minParallelWorkers,
        max: maxParallelWorkers,
      ),
      cacheTtlSeconds: clampedIntFromValue(
        json['cache_ttl_seconds'],
        fallback: defaultCacheTtlSeconds,
        min: minCacheTtlSeconds,
        max: maxCacheTtlSeconds,
      ),
      cacheMaxBytes: clampedIntFromValue(
        json['cache_max_bytes'],
        fallback: defaultCacheMaxBytes,
        min: minCacheMaxBytes,
        max: maxCacheMaxBytes,
      ),
      cooldownTier1Failures: clampedIntFromValue(
        json['cooldown_tier1_failures'],
        fallback: defaultCooldownTier1Failures,
        min: minCooldownFailures,
        max: maxCooldownFailures,
      ),
      cooldownTier1Seconds: clampedIntFromValue(
        json['cooldown_tier1_seconds'],
        fallback: defaultCooldownTier1Seconds,
        min: minCooldownSeconds,
        max: maxCooldownSeconds,
      ),
      cooldownTier2Failures: clampedIntFromValue(
        json['cooldown_tier2_failures'],
        fallback: defaultCooldownTier2Failures,
        min: minCooldownFailures,
        max: maxCooldownFailures,
      ),
      cooldownTier2Seconds: clampedIntFromValue(
        json['cooldown_tier2_seconds'],
        fallback: defaultCooldownTier2Seconds,
        min: minCooldownSeconds,
        max: maxCooldownSeconds,
      ),
      cooldownTier3Failures: clampedIntFromValue(
        json['cooldown_tier3_failures'],
        fallback: defaultCooldownTier3Failures,
        min: minCooldownFailures,
        max: maxCooldownFailures,
      ),
      cooldownTier3Seconds: clampedIntFromValue(
        json['cooldown_tier3_seconds'],
        fallback: defaultCooldownTier3Seconds,
        min: minCooldownSeconds,
        max: maxCooldownSeconds,
      ),
      cooldownQuotaSeconds: clampedIntFromValue(
        json['cooldown_quota_seconds'],
        fallback: defaultCooldownQuotaSeconds,
        min: minCooldownSeconds,
        max: maxCooldownSeconds,
      ),
      alertSuccessRatePct: clampedIntFromValue(
        json['alert_success_rate_pct'],
        fallback: 0,
        min: 0,
        max: maxAlertSuccessRatePct,
      ),
      alertAvgDurationMs: clampedIntFromValue(
        json['alert_avg_duration_ms'],
        fallback: 0,
        min: 0,
        max: maxAlertAvgDurationMs,
      ),
      throttlePerMinute: clampedIntFromValue(
        json['throttle_per_minute'],
        fallback: 0,
        min: 0,
        max: maxThrottlePerMinute,
      ),
    );
  }
}
