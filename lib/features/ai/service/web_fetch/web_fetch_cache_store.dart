import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../model/ai_web_fetch_settings.dart';
import '../web_engine/web_engine_cache_store_base.dart';

/// URL → 抓取内容元数据 + 内容文件的本地持久化缓存。
///
/// 公共骨架（串行写入 / clearAll / totalBytesOnDisk / prewarm / LRU 淘汰 /
/// 过期回收 / 孤儿清理）由 [WebEngineCacheStoreBase] 接管；本类只负责：
/// * 计算 key（URL + prompt + 会影响最终 focused answer 的设置 / 模型）
/// * 把基础 [WebEngineCacheRawLookup] 封装成包含 `content` 的领域结构
/// * 在 store 时塞入领域专属 metadata（`url` 字段 + 调用方传入的扩展元数据）
class WebFetchCacheStore extends WebEngineCacheStoreBase<AiWebFetchSettings> {
  WebFetchCacheStore._();

  static final WebFetchCacheStore instance = WebFetchCacheStore._();

  @override
  String get subdir => 'web_fetch';

  @override
  String get logTag => 'web_fetch_cache';

  @override
  String get payloadPathField => 'content_path';

  @override
  String get payloadBytesField => 'content_bytes';

  @override
  String get payloadCharsField => 'content_chars';

  @override
  bool isCacheEnabled(AiWebFetchSettings settings) => settings.cacheEnabled;

  @override
  int cacheTtlSeconds(AiWebFetchSettings settings) => settings.cacheTtlSeconds;

  @override
  int cacheMaxBytes(AiWebFetchSettings settings) => settings.cacheMaxBytes;

  /// 缓存键：URL + 用户 prompt + 调度/引擎/模型。
  ///
  /// WebFetch 缓存的是最终 focused answer，不只是原始页面正文；因此引擎顺序
  /// （串行短路）、并行模式、引擎端点、重试/超时、权重、截断阈值与会话模型都
  /// 要进入 key，避免用户调整设置或切模型后读到旧答案。
  static String computeKey({
    required String url,
    required String prompt,
    required AiWebFetchSettings settings,
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
            'connection_timeout_seconds': e.connectionTimeoutSeconds,
            'response_timeout_seconds': e.responseTimeoutSeconds,
            'provider_config_id': e.providerConfigId?.trim() ?? '',
            'endpoint_override': e.endpointOverride?.trim() ?? '',
          },
        )
        .toList(growable: false);
    final payload = jsonEncode(<String, Object?>{
      'url': url.trim(),
      'prompt': prompt.trim(),
      'engines': enabled,
      'parallel': settings.parallel,
      'workers': settings.parallelWorkers,
      'model_protocol': modelProtocol,
      'model_id': modelId,
      'model_config_id': modelConfigId,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<WebFetchCacheLookup?> lookup({
    required String key,
    required AiWebFetchSettings settings,
  }) async {
    final raw = await baseLookup(key: key, settings: settings);
    if (raw == null) return null;
    return WebFetchCacheLookup(
      content: raw.payload,
      metadata: Map<String, Object?>.unmodifiable(
        Map<String, Object?>.of(raw.metadata)..remove('response_headers'),
      ),
      cachedAt: raw.cachedAt,
      expiresAt: raw.expiresAt,
    );
  }

  Future<void> store({
    required String key,
    required AiWebFetchSettings settings,
    required String url,
    required String content,
    required Map<String, Object?> metadata,
  }) {
    return baseStore(
      key: key,
      settings: settings,
      payload: content,
      extraEntryFields: <String, Object?>{'url': url, ...metadata},
    );
  }
}

class WebFetchCacheLookup {
  const WebFetchCacheLookup({
    required this.content,
    required this.metadata,
    required this.cachedAt,
    required this.expiresAt,
  });

  final String content;
  final Map<String, Object?> metadata;
  final DateTime cachedAt;
  final DateTime expiresAt;
}
