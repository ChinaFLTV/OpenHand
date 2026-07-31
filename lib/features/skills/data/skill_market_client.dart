import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/net/abortable_http_request.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/net/http_status_utils.dart';
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
  static const int _maxDownloadBytes = 48 * kBytesPerMiB;
  static const int _maxJsonResponseBytes = 4 * kBytesPerMiB;
  static const int _maxTextResponseBytes = 4 * kBytesPerMiB;
  static const int _maxSearchCacheEntries = 32;
  static const int _maxMetadataCacheEntries = 128;
  static const int _maxFileContentCacheEntries = 128;
  static const int _maxBundleCacheEntries = 64;
  static const Duration _requestTimeout = Duration(seconds: 14);
  static const Duration _downloadIdleTimeout = Duration(seconds: 18);
  static const Duration _downloadTotalTimeout = Duration(minutes: 5);
  static const Duration _discardIdleTimeout = Duration(seconds: 2);
  static const Duration _discardTotalTimeout = Duration(seconds: 4);
  static const String _skillManifestPath = 'SKILL.MD';

  final http.Client _client;
  final bool _ownsClient;
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
      );
  final LifecycleLruCache<Future<SkillMarketBundle>> _bundleCache =
      LifecycleLruCache<Future<SkillMarketBundle>>(
        maxEntries: _maxBundleCacheEntries,
      );

  void close() {
    _clearCaches();
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
    final normalizedPageSize = pageSize < 1 ? defaultPageSize : pageSize;
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
    final normalizedSlug = _normalizeSlug(slug);
    if (normalizedSlug == null) {
      return Future<SkillMarketBundle>.error(
        const SkillMarketException('Skill slug is empty.'),
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
    );
  }

  Future<Uint8List> downloadSkillArchive(String slug) async {
    final normalizedSlug = _normalizeSlug(slug);
    if (normalizedSlug == null) {
      throw const SkillMarketException('Skill slug is empty.');
    }

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
    );
    if (isHttpFailureStatus(response.statusCode)) {
      // 抛错前排空响应流，确保连接正常回收。
      await _drainResponseStreamBestEffort(
        response.stream,
        reason: '下载响应异常后排空响应流',
      );
      _throwHttpFailure(response.statusCode, 'while downloading skill');
    }
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > _maxDownloadBytes) {
      await _drainResponseStreamBestEffort(
        response.stream,
        reason: '下载内容超限后排空响应流',
      );
      throw const SkillMarketException('Skill archive is too large.');
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
      throw const SkillMarketException('Skill archive is too large.');
    }
    if (bytes.isEmpty) {
      throw const SkillMarketException('Downloaded skill archive is empty.');
    }
    return bytes;
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
    final normalizedSlug = _normalizeSlug(slug);
    if (normalizedSlug == null) {
      throw const SkillMarketException('Skill slug is empty.');
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
    final normalizedSlug = _normalizeSlug(slug);
    if (normalizedSlug == null) {
      throw const SkillMarketException('Skill slug is empty.');
    }
    final normalizedVersion = _normalizeVersion(version);
    if (normalizedVersion.isEmpty) {
      throw const SkillMarketException('Skill version is empty.');
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
    final normalizedSlug = _normalizeSlug(slug);
    if (normalizedSlug == null) {
      throw const SkillMarketException('Skill slug is empty.');
    }
    final normalizedPath = nullIfBlank(path);
    if (normalizedPath == null) {
      throw const SkillMarketException('Skill file path is empty.');
    }
    final normalizedVersion = _normalizeVersion(version);
    if (normalizedVersion.isEmpty) {
      throw const SkillMarketException('Skill version is empty.');
    }
    return _cached(
      _fileContentCache,
      '$normalizedSlug|$normalizedVersion|$normalizedPath',
      () async {
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
        );
        if (isHttpFailureStatus(response.statusCode)) {
          await _drainResponseStreamBestEffort(
            response.stream,
            reason: '技能文件响应异常后排空响应流',
          );
        }
        _throwHttpFailure(response.statusCode, 'while fetching skill file');
        try {
          return await readBoundedByteStreamText(
            response.stream,
            maxBytes: _maxTextResponseBytes,
            idleTimeout: _requestTimeout,
            totalTimeout: _requestTimeout,
            allowMalformed: true,
          );
        } on ByteStreamSizeLimitException {
          throw const SkillMarketException('Skill file response is too large.');
        }
      },
    );
  }

  Future<SkillMarketVersionsResult> fetchSkillVersions(String slug) async {
    final normalizedSlug = _normalizeSlug(slug);
    if (normalizedSlug == null) {
      throw const SkillMarketException('Skill slug is empty.');
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

  String? _normalizeSlug(String slug) => nullIfBlank(slug);

  String _normalizeVersion(String? version) => nullIfBlank(version) ?? '';

  Future<Map<String, Object?>> _getJson(Uri uri) async {
    final request = http.Request('GET', uri)
      ..headers[HttpHeaders.acceptHeader] = 'application/json';
    final response = await sendAbortableHttpRequest(
      client: _client,
      request: request,
      connectionTimeout: _requestTimeout,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      await _drainResponseStreamBestEffort(
        response.stream,
        reason: 'JSON 响应异常后排空响应流',
      );
      _throwHttpFailure(response.statusCode, 'from $uri');
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
      throw const SkillMarketException('Skill market response is too large.');
    }
    final decoded = jsonDecode(utf8.decode(body));
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
    throw const FormatException('Skill market response is not a JSON object.');
  }

  void _ensureEnvelopeSucceeded(Map<String, Object?> json) {
    final code = json['code'];
    final succeeded = code == null || code == 0 || code == '0';
    if (succeeded) {
      return;
    }
    final message = json['message'];
    throw SkillMarketException(
      message == null ? 'Skill market request failed.' : '$message',
    );
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

  void _throwHttpFailure(int statusCode, String context) {
    if (!isHttpFailureStatus(statusCode)) return;
    throw SkillMarketException('HTTP $statusCode $context.');
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
    Future<T> Function() loader,
  ) {
    final cached = cache.get(key);
    if (cached != null) {
      return cached;
    }
    late final Future<T> future;
    future = Future<T>.sync(loader).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      cache.removeIfIdentical(key, future);
      Error.throwWithStackTrace(error, stackTrace);
    });
    cache.put(key, future);
    return future;
  }
}
