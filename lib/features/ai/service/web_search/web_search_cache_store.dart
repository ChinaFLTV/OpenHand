import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_web_search_settings.dart';
import '../web_engine/web_engine_cache_store_base.dart';

/// 关键词 → summary 元数据的本地持久化缓存。
///
/// 共享骨架（串行写入 / clearAll / totalBytesOnDisk / prewarm / LRU 淘汰 /
/// 过期回收 / 孤儿清理）由 [WebEngineCacheStoreBase] 接管；本类只负责：
/// * 计算 key（覆盖 query + 引擎 / locale / summary 风格等会污染结果的设置）
/// * 把基础 [WebEngineCacheRawLookup] 封装成包含 `summary` 的领域结构
/// * 在 store 时塞入领域专属 metadata（`query` 字段 + 调用方传入的扩展元数据）
class WebSearchCacheStore extends WebEngineCacheStoreBase<AiWebSearchSettings> {
  WebSearchCacheStore._();

  static final WebSearchCacheStore instance = WebSearchCacheStore._();

  @override
  String get subdir => 'web_search';

  @override
  String get logTag => 'web_search_cache';

  @override
  String get payloadPathField => 'summary_path';

  @override
  String get payloadBytesField => 'summary_bytes';

  @override
  String get payloadCharsField => 'summary_chars';

  @override
  bool isCacheEnabled(AiWebSearchSettings settings) => settings.cacheEnabled;

  @override
  int cacheTtlSeconds(AiWebSearchSettings settings) => settings.cacheTtlSeconds;

  @override
  int cacheMaxBytes(AiWebSearchSettings settings) => settings.cacheMaxBytes;

  /// 计算缓存键：覆盖 query、引擎、摘要模型、结果数、风格/长度和语言环境。
  /// 任何会显著影响 summary 内容的设置都参与摘要，避免脏读。
  static String computeKey({
    required String query,
    required AiWebSearchSettings settings,
    required List<String> allowedDomains,
    required List<String> blockedDomains,
    required String localeTag,
    required String modelProtocol,
    required String modelId,
    required String modelConfigId,
  }) {
    final enabled = settings
        .enabledEnginesInOrder()
        .map(
          (e) => <String, Object?>{
            'kind': e.kind.name,
            'weight': e.weight,
            'max_retries': e.maxRetries,
            'truncation_chars': e.truncationChars,
            'provider_config_id': e.providerConfigId?.trim() ?? '',
            'endpoint_override': e.endpointOverride?.trim() ?? '',
          },
        )
        .toList(growable: false);
    final allow = [...allowedDomains]..sort();
    final block = [...blockedDomains]..sort();
    final payload = jsonEncode(<String, Object?>{
      'q': lowercaseStringFromValue(query),
      'engines': enabled,
      'allow': allow,
      'block': block,
      'r': settings.resultCount,
      'd': settings.summaryDetail.name,
      's': settings.summaryStyle.name,
      'min': settings.summaryMinChars,
      'max': settings.summaryMaxChars,
      'mode': settings.modelMode.name,
      'fixed':
          '${settings.fixedModelProviderConfigId ?? ''}/${settings.fixedModelId ?? ''}',
      'parallel': settings.parallel,
      'workers': settings.parallelWorkers,
      'locale': localeTag,
      'model_protocol': modelProtocol,
      'model_id': modelId,
      'model_config_id': modelConfigId,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// 读取一条缓存。命中 + 未过期返回 [WebSearchCacheLookup]，否则 null。
  Future<WebSearchCacheLookup?> lookup({
    required String key,
    required AiWebSearchSettings settings,
  }) async {
    final raw = await baseLookup(key: key, settings: settings);
    if (raw == null) return null;
    return WebSearchCacheLookup(
      summary: raw.payload,
      metadata: raw.metadata,
      cachedAt: raw.cachedAt,
      expiresAt: raw.expiresAt,
    );
  }

  /// 写入一条新的缓存。空 summary 直接忽略。
  Future<void> store({
    required String key,
    required AiWebSearchSettings settings,
    required String query,
    required String summary,
    required Map<String, Object?> metadata,
  }) {
    return baseStore(
      key: key,
      settings: settings,
      payload: summary,
      extraEntryFields: <String, Object?>{'query': query, ...metadata},
    );
  }
}

class WebSearchCacheLookup {
  const WebSearchCacheLookup({
    required this.summary,
    required this.metadata,
    required this.cachedAt,
    required this.expiresAt,
  });

  final String summary;
  final Map<String, Object?> metadata;
  final DateTime cachedAt;
  final DateTime expiresAt;
}
