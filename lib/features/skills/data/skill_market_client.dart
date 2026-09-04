import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/net/abortable_http_request.dart';
import '../../../shared/net/http_redirect_utils.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/net/http_status_utils.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_json_conversion.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/lifecycle_cache.dart';
import '../model/skill_market.dart';

class SkillMarketException implements Exception {
  const SkillMarketException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SkillMarketClient {
  SkillMarketClient({http.Client? httpClient})
    : _client = httpClient ?? SystemProxyResolver.instance.createHttpClient(),
      _ownsClient = httpClient == null;

  static const String _host = 'api.skillhub.cn';
  static const int defaultPageSize = 24;
  static const int maxPageSize = 200;
  static const int _maxDownloadBytes = 48 * kBytesPerMiB;
  static const int _maxJsonResponseBytes = 4 * kBytesPerMiB;
  static const BoundedJsonConversionConfig _jsonConversionConfig =
      BoundedJsonConversionConfig(
        maxContainerItems: 65536,
        maxTotalNodes: 524288,
      );
  static const int _maxTextResponseBytes = 4 * kBytesPerMiB;
  static const int _maxSearchCacheEntries = 32;
  static const int _maxMetadataCacheEntries = 128;
  static const int _maxFileContentCacheEntries = 128;
  static const int _maxBundleCacheEntries = 64;
  static const int _maxFileContentCacheCharacters = 32 * kBytesPerMiB;
  static const int _maxBundleCacheCharacters = 32 * kBytesPerMiB;
  static const int _maxConcurrentRequests = 8;
  static const int _maxQueuedRequests = 64;
  static const Duration _requestQueueTimeout = Duration(seconds: 30);
  static const Duration _requestTimeout = Duration(seconds: 14);
  static const Duration _downloadIdleTimeout = Duration(seconds: 18);
  static const Duration _downloadTotalTimeout = Duration(minutes: 5);
  static const Duration _discardIdleTimeout = Duration(seconds: 2);
  static const Duration _discardTotalTimeout = Duration(seconds: 4);
  static const String _skillManifestPath = 'SKILL.MD';

  final http.Client _client;
  final bool _ownsClient;
  final OpenHandAsyncSemaphore _requestSlots = OpenHandAsyncSemaphore(
    _maxConcurrentRequests,
    maxWaiters: _maxQueuedRequests,
  );
  final Set<Completer<void>> _activeRequestAborts = <Completer<void>>{};
  bool _closed = false;
  final LifecycleLruCache<Future<SkillMarketSearchResult>> _searchCache =
      LifecycleLruCache<Future<SkillMarketSearchResult>>(
        maxEntries: _maxSearchCacheEntries,
      );
  final LifecycleLruCache<Future<SkillMarketDetail>> _detailCache =
      LifecycleLruCache<Future<SkillMarketDetail>>(
        maxEntries: _maxMetadataCacheEntries,
      );
  final LifecycleLruCache<Future<SkillMarketVersionsResult>> _versionsCache =
      LifecycleLruCache<Future<SkillMarketVersionsResult>>(
        maxEntries: _maxMetadataCacheEntries,
      );
  final LifecycleLruCache<Future<SkillMarketFilesResult>> _filesCache =
      LifecycleLruCache<Future<SkillMarketFilesResult>>(
        maxEntries: _maxMetadataCacheEntries,
      );
  final LifecycleLruCache<Future<String>> _fileContentCache =
      LifecycleLruCache<Future<String>>(
        maxEntries: _maxFileContentCacheEntries,
        maxCost: _maxFileContentCacheCharacters,
      );
  final LifecycleLruCache<Future<SkillMarketBundle>> _bundleCache =
      LifecycleLruCache<Future<SkillMarketBundle>>(
        maxEntries: _maxBundleCacheEntries,
        maxCost: _maxBundleCacheCharacters,
      );

  void close() {
    if (_closed) return;
    _closed = true;
    _requestSlots.cancelWaiters();
    _clearCaches();
    for (final abort in _activeRequestAborts.toList(growable: false)) {
      if (!abort.isCompleted) abort.complete();
    }
    _activeRequestAborts.clear();
    if (_ownsClient) {
      _client.close();
    }
  }

  void clearSearchCache() {
    _searchCache.clear();
  }

  Future<SkillMarketSearchResult> searchSkills({
    required String keyword,
    required int page,
    int pageSize = defaultPageSize,
  }) {
    final normalizedKeyword = nullIfBlank(keyword) ?? '';
    final normalizedPage = page < 1 ? 1 : page;
    final normalizedPageSize = pageSize < 1
        ? defaultPageSize
        : pageSize > maxPageSize
        ? maxPageSize
        : pageSize;
    final cacheKey = '$normalizedPage|$normalizedPageSize|$normalizedKeyword';
    return _cached(
      _searchCache,
      cacheKey,
      () => _fetchSearch(
        keyword: normalizedKeyword,
        page: normalizedPage,
        pageSize: normalizedPageSize,
      ),
    );
  }

  Future<SkillMarketBundle> loadSkillBundle(String slug, {String? version}) {
    final normalizedSlug = nullIfBlank(slug);
    if (normalizedSlug == null) {
      return Future<SkillMarketBundle>.error(
        const SkillMarketException('技能标识不能为空。'),
      );
    }
    final normalizedVersion = _normalizeVersion(version);
    final cacheKey = '$normalizedSlug|$normalizedVersion';
    return _cached(
      _bundleCache,
      cacheKey,
      () => _fetchSkillBundle(
        normalizedSlug,
        requestedVersion: normalizedVersion,
      ),
      resultCost: (bundle) => bundle.skillMarkdown?.length ?? 0,
    );
  }

  Future<Uint8List> downloadSkillArchive(String slug) async {
    final normalizedSlug = nullIfBlank(slug);
    if (normalizedSlug == null) {
      throw const SkillMarketException('技能标识不能为空。');
    }

    return _runAbortableRequest((cancelSignal) async {
      final request = http.Request(
        'GET',
        Uri.https(_host, '/api/v1/download', <String, String>{
          'slug': normalizedSlug,
        }),
      );
      request.headers[HttpHeaders.acceptHeader] =
          'application/zip, application/octet-stream, */*';

      final response = await sendAbortableHttpRequest(
        client: _client,
        request: request,
        connectionTimeout: _requestTimeout,
        cancelSignal: cancelSignal,
      );
      if (isHttpFailureStatus(response.statusCode)) {
        // 抛错前排空响应流，确保连接正常回收。
        await _drainResponseStreamBestEffort(
          response.stream,
          reason: '下载响应异常后排空响应流',
        );
        _throwHttpFailure(response.statusCode, '下载技能');
      }
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > _maxDownloadBytes) {
        await _drainResponseStreamBestEffort(
          response.stream,
          reason: '下载内容超限后排空响应流',
        );
        throw const SkillMarketException('技能归档超过大小上限。');
      }

      late final Uint8List bytes;
      try {
        bytes = await readBoundedByteStream(
          response.stream,
          maxBytes: _maxDownloadBytes,
          idleTimeout: _downloadIdleTimeout,
          totalTimeout: _downloadTotalTimeout,
        );
      } on ByteStreamSizeLimitException {
        throw const SkillMarketException('技能归档超过大小上限。');
      }
      if (bytes.isEmpty) {
        throw const SkillMarketException('下载的技能归档为空。');
      }
      return bytes;
    });
  }

  Future<SkillMarketSearchResult> _fetchSearch({
    required String keyword,
    required int page,
    required int pageSize,
  }) async {
    final queryParameters = <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      'sortBy': 'score',
      'order': 'desc',
      if (keyword.isNotEmpty) 'keyword': keyword,
    };
    final json = await _getJson(
      Uri.https(_host, '/api/skills', queryParameters),
    );
    _ensureEnvelopeSucceeded(json);
    return SkillMarketSearchResult.fromJson(
      json,
      page: page,
      pageSize: pageSize,
    );
  }

  Future<SkillMarketBundle> _fetchSkillBundle(
    String slug, {
    required String requestedVersion,
  }) async {
    final detail = await fetchSkillDetail(slug);
    final resolvedVersion = _resolveVersion(detail, requestedVersion);
    final versionsFuture = fetchSkillVersions(slug).then(
      (result) => result.versions,
      onError: (Object error, StackTrace stackTrace) {
        silentLog('skill_market_client', '获取技能版本 $slug', error, stackTrace);
        return const <SkillMarketVersion>[];
      },
    );
    final filesFuture = resolvedVersion.isEmpty
        ? Future<SkillMarketFilesResult?>.value()
        : fetchSkillFiles(slug, resolvedVersion).then<SkillMarketFilesResult?>(
            (result) => result,
            onError: (Object error, StackTrace stackTrace) {
              silentLog(
                'skill_market_client',
                '获取技能文件 $slug',
                error,
                stackTrace,
              );
              return null;
            },
          );

    final versions = await versionsFuture;
    final files = await filesFuture;
    final skillMarkdown = await _bestEffortReadSkillMarkdown(
      slug: slug,
      version: resolvedVersion,
      files: files,
    );

    return SkillMarketBundle(
      detail: detail,
      files: files,
      versions: versions,
      skillMarkdown: skillMarkdown,
      resolvedVersion: resolvedVersion,
    );
  }

  Future<SkillMarketDetail> fetchSkillDetail(String slug) async {
    final normalizedSlug = nullIfBlank(slug);
    if (normalizedSlug == null) {
      throw const SkillMarketException('技能标识不能为空。');
    }
    return _cached(_detailCache, normalizedSlug, () async {
      final json = await _getJson(
        Uri.https(_host, '/api/v1/skills/$normalizedSlug'),
      );
      return SkillMarketDetail.fromJson(json);
    });
  }

  Future<SkillMarketFilesResult> fetchSkillFiles(
    String slug,
    String version,
  ) async {
    final normalizedSlug = nullIfBlank(slug);
    if (normalizedSlug == null) {
      throw const SkillMarketException('技能标识不能为空。');
    }
    final normalizedVersion = _normalizeVersion(version);
    if (normalizedVersion.isEmpty) {
      throw const SkillMarketException('技能版本不能为空。');
    }
    return _cached(_filesCache, '$normalizedSlug|$normalizedVersion', () async {
      final json = await _getJson(
        Uri.https(
          _host,
          '/api/v1/skills/$normalizedSlug/files',
          <String, String>{'version': normalizedVersion},
        ),
      );
      return SkillMarketFilesResult.fromJson(json);
    });
  }

  Future<String> fetchSkillFileContent({
    required String slug,
    required String path,
    required String version,
  }) async {
    final normalizedSlug = nullIfBlank(slug);
    if (normalizedSlug == null) {
      throw const SkillMarketException('技能标识不能为空。');
    }
    final normalizedPath = nullIfBlank(path);
    if (normalizedPath == null) {
      throw const SkillMarketException('技能文件路径不能为空。');
    }
    final normalizedVersion = _normalizeVersion(version);
    if (normalizedVersion.isEmpty) {
      throw const SkillMarketException('技能版本不能为空。');
    }
    return _cached(
      _fileContentCache,
      '$normalizedSlug|$normalizedVersion|$normalizedPath',
      () => _runAbortableRequest((cancelSignal) async {
        final request = http.Request(
          'GET',
          Uri.https(
            _host,
            '/api/v1/skills/$normalizedSlug/file',
            <String, String>{
              'path': normalizedPath,
              'version': normalizedVersion,
            },
          ),
        )..headers[HttpHeaders.acceptHeader] = 'text/plain, */*';
        final response = await sendAbortableHttpRequest(
          client: _client,
          request: request,
          connectionTimeout: _requestTimeout,
          cancelSignal: cancelSignal,
        );
        if (isHttpFailureStatus(response.statusCode)) {
          await _drainResponseStreamBestEffort(
            response.stream,
            reason: '技能文件响应异常后排空响应流',
          );
        }
        _throwHttpFailure(response.statusCode, '获取技能文件');
        try {
          return await readBoundedByteStreamText(
            response.stream,
            maxBytes: _maxTextResponseBytes,
            idleTimeout: _requestTimeout,
            totalTimeout: _requestTimeout,
            allowMalformed: true,
          );
        } on ByteStreamSizeLimitException {
          throw const SkillMarketException('技能文件响应超过大小上限。');
        }
      }),
      resultCost: (content) => content.length,
    );
  }

  Future<SkillMarketVersionsResult> fetchSkillVersions(String slug) async {
    final normalizedSlug = nullIfBlank(slug);
    if (normalizedSlug == null) {
      throw const SkillMarketException('技能标识不能为空。');
    }
    return _cached(_versionsCache, normalizedSlug, () async {
      final json = await _getJson(
        Uri.https(_host, '/api/v1/skills/$normalizedSlug/versions'),
      );
      return SkillMarketVersionsResult.fromJson(json);
    });
  }

  Future<String?> _bestEffortReadSkillMarkdown({
    required String slug,
    required String version,
    required SkillMarketFilesResult? files,
  }) async {
    if (version.isEmpty || files == null) {
      return null;
    }
    SkillMarketFileEntry? skillManifest;
    for (final file in files.files) {
      if (nullIfBlank(file.path)?.toUpperCase() == _skillManifestPath) {
        skillManifest = file;
        break;
      }
    }
    if (skillManifest == null) {
      return null;
    }

    try {
      return await fetchSkillFileContent(
        slug: slug,
        path: skillManifest.path,
        version: version,
      );
    } catch (error, stackTrace) {
      silentLog('skill_market_client', '获取 SKILL.md $slug', error, stackTrace);
      return null;
    }
  }

  String _resolveVersion(SkillMarketDetail detail, String requestedVersion) {
    final normalizedRequestedVersion = _normalizeVersion(requestedVersion);
    if (normalizedRequestedVersion.isNotEmpty) {
      return normalizedRequestedVersion;
    }
    final latestVersion = _normalizeVersion(detail.latestVersion?.version);
    if (latestVersion.isNotEmpty) {
      return latestVersion;
    }
    final latestTag = _normalizeVersion(detail.skill.latestTag);
    if (latestTag.isNotEmpty) {
      return latestTag;
    }
    return '';
  }

  String _normalizeVersion(String? version) => nullIfBlank(version) ?? '';

  Future<Map<String, Object?>> _getJson(Uri uri) async {
    return _runAbortableRequest((cancelSignal) async {
      final request = http.Request('GET', uri)
        ..headers[HttpHeaders.acceptHeader] = kApplicationJsonMimeType;
      final response = await sendAbortableHttpRequest(
        client: _client,
        request: request,
        connectionTimeout: _requestTimeout,
        cancelSignal: cancelSignal,
      );
      if (isHttpFailureStatus(response.statusCode)) {
        await _drainResponseStreamBestEffort(
          response.stream,
          reason: 'JSON 响应异常后排空响应流',
        );
        _throwHttpFailure(response.statusCode, '请求 $uri');
      }
      late final Uint8List body;
      try {
        body = await readBoundedByteStream(
          response.stream,
          maxBytes: _maxJsonResponseBytes,
          idleTimeout: _requestTimeout,
          totalTimeout: _requestTimeout,
        );
      } on ByteStreamSizeLimitException {
        throw const SkillMarketException('技能市场响应超过大小上限。');
      }
      final decoded = decodeJsonTextUsingConfig(
        utf8.decode(body),
        maxTextCodeUnits: _maxJsonResponseBytes,
        config: _jsonConversionConfig,
      );
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
      throw const FormatException('技能市场响应不是 JSON 对象。');
    });
  }

  void _ensureEnvelopeSucceeded(Map<String, Object?> json) {
    final code = json['code'];
    final succeeded = code == null || code == 0 || code == '0';
    if (succeeded) {
      return;
    }
    final message = json['message'];
    throw SkillMarketException(message == null ? '技能市场请求失败。' : '$message');
  }

  Future<void> _drainResponseStreamBestEffort(
    Stream<List<int>> stream, {
    required String reason,
  }) async {
    try {
      await drainByteStreamWithTimeout(
        stream,
        idleTimeout: _discardIdleTimeout,
        totalTimeout: _discardTotalTimeout,
      );
    } catch (error, stack) {
      silentLog('skill_market_client', reason, error, stack);
    }
  }

  void _throwHttpFailure(int statusCode, String action) {
    if (!isHttpFailureStatus(statusCode)) return;
    throw SkillMarketException('$action失败，HTTP 状态码 $statusCode。');
  }

  void _clearCaches() {
    _searchCache.clear();
    _detailCache.clear();
    _versionsCache.clear();
    _filesCache.clear();
    _fileContentCache.clear();
    _bundleCache.clear();
  }

  Future<T> _cached<T>(
    LifecycleLruCache<Future<T>> cache,
    String key,
    Future<T> Function() loader, {
    int Function(T value)? resultCost,
  }) {
    if (_closed) {
      return Future<T>.error(StateError('技能市场客户端已关闭。'));
    }
    final cached = cache.get(key);
    if (cached != null) {
      return cached;
    }
    late final Future<T> future;
    future = Future<T>.sync(loader)
        .then((value) {
          final cost = resultCost?.call(value);
          if (cost != null) {
            cache.updateCostIfIdentical(key, future, key.length + cost);
          }
          return value;
        })
        .catchError((Object error, StackTrace stackTrace) {
          cache.removeIfIdentical(key, future);
          Error.throwWithStackTrace(error, stackTrace);
        });
    cache.put(key, future);
    return future;
  }

  Future<T> _runAbortableRequest<T>(
    Future<T> Function(Future<void> cancelSignal) operation,
  ) async {
    if (_closed) throw StateError('技能市场客户端已关闭。');
    late final bool acquired;
    try {
      acquired = await _requestSlots.acquireWithin(_requestQueueTimeout);
    } on StateError {
      if (_closed) throw StateError('技能市场客户端已关闭。');
      throw const SkillMarketException('技能市场请求排队已满。');
    }
    if (!acquired) {
      if (_closed) throw StateError('技能市场客户端已关闭。');
      throw TimeoutException('技能市场请求排队超时。', _requestQueueTimeout);
    }
    if (_closed) {
      _requestSlots.release();
      throw StateError('技能市场客户端已关闭。');
    }
    final abort = Completer<void>();
    _activeRequestAborts.add(abort);
    try {
      return await operation(abort.future);
    } finally {
      if (!abort.isCompleted) abort.complete();
      _activeRequestAborts.remove(abort);
      _requestSlots.release();
    }
  }
}
