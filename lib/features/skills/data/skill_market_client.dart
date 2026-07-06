import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/net/http_status_utils.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/skill_market.dart';

class SkillMarketException implements Exception {
  const SkillMarketException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SkillMarketClient {
  SkillMarketClient({http.Client? httpClient})
    : _client = httpClient ?? SystemProxyResolver.instance.createHttpClient();

  static const String _host = 'api.skillhub.cn';
  static const int defaultPageSize = 24;
  static const int _maxDownloadBytes = 48 * 1024 * 1024;
  static const Duration _requestTimeout = Duration(seconds: 14);
  static const Duration _downloadIdleTimeout = Duration(seconds: 18);
  static const String _skillManifestPath = 'SKILL.MD';

  final http.Client _client;
  final Map<String, Future<SkillMarketSearchResult>> _searchCache =
      <String, Future<SkillMarketSearchResult>>{};
  final Map<String, Future<SkillMarketDetail>> _detailCache =
      <String, Future<SkillMarketDetail>>{};
  final Map<String, Future<SkillMarketVersionsResult>> _versionsCache =
      <String, Future<SkillMarketVersionsResult>>{};
  final Map<String, Future<SkillMarketFilesResult>> _filesCache =
      <String, Future<SkillMarketFilesResult>>{};
  final Map<String, Future<String>> _fileContentCache =
      <String, Future<String>>{};
  final Map<String, Future<SkillMarketBundle>> _bundleCache =
      <String, Future<SkillMarketBundle>>{};

  void close() {
    _client.close();
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
    final cached = _searchCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final future =
        _fetchSearch(
          keyword: normalizedKeyword,
          page: normalizedPage,
          pageSize: normalizedPageSize,
        ).catchError((Object error, StackTrace stackTrace) {
          _searchCache.remove(cacheKey);
          Error.throwWithStackTrace(error, stackTrace);
        });
    _searchCache[cacheKey] = future;
    return future;
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
    final cached = _bundleCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final future =
        _fetchSkillBundle(
          normalizedSlug,
          requestedVersion: normalizedVersion,
        ).catchError((Object error, StackTrace stackTrace) {
          _bundleCache.remove(cacheKey);
          Error.throwWithStackTrace(error, stackTrace);
        });
    _bundleCache[cacheKey] = future;
    return future;
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

    final response = await _client.send(request).timeout(_requestTimeout);
    if (isHttpFailureStatus(response.statusCode)) {
      // Drain the body before throwing so the underlying connection can be
      // returned to the pool / closed cleanly instead of leaking.
      await _drainResponseStreamBestEffort(
        response.stream,
        reason: 'drain stream after non-2xx download',
      );
      _throwHttpFailure(response.statusCode, 'while downloading skill');
    }
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > _maxDownloadBytes) {
      await _drainResponseStreamBestEffort(
        response.stream,
        reason: 'drain oversized download stream',
      );
      throw const SkillMarketException('Skill archive is too large.');
    }

    final builder = BytesBuilder(copy: false);
    var downloadedBytes = 0;
    await for (final chunk in response.stream.timeout(_downloadIdleTimeout)) {
      downloadedBytes += chunk.length;
      if (downloadedBytes > _maxDownloadBytes) {
        throw const SkillMarketException('Skill archive is too large.');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
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
        silentLog(
          'skill_market_client',
          'fetch versions $slug',
          error,
          stackTrace,
        );
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
                'fetch files $slug',
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
        final response = await _client
            .get(
              Uri.https(
                _host,
                '/api/v1/skills/$normalizedSlug/file',
                <String, String>{
                  'path': normalizedPath,
                  'version': normalizedVersion,
                },
              ),
              headers: <String, String>{
                HttpHeaders.acceptHeader: 'text/plain, */*',
              },
            )
            .timeout(_requestTimeout);
        _throwHttpFailure(response.statusCode, 'while fetching skill file');
        return utf8.decode(response.bodyBytes, allowMalformed: true);
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
      silentLog(
        'skill_market_client',
        'fetch SKILL.md $slug',
        error,
        stackTrace,
      );
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
    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'application/json',
          },
        )
        .timeout(_requestTimeout);
    _throwHttpFailure(response.statusCode, 'from $uri');
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
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
      await stream.drain<void>();
    } catch (error, stack) {
      silentLog('skill_market_client', reason, error, stack);
    }
  }

  void _throwHttpFailure(int statusCode, String context) {
    if (!isHttpFailureStatus(statusCode)) return;
    throw SkillMarketException('HTTP $statusCode $context.');
  }

  Future<T> _cached<T>(
    Map<String, Future<T>> cache,
    String key,
    Future<T> Function() loader,
  ) {
    final cached = cache[key];
    if (cached != null) {
      return cached;
    }
    final future = loader().catchError((Object error, StackTrace stackTrace) {
      cache.remove(key);
      Error.throwWithStackTrace(error, stackTrace);
    });
    cache[key] = future;
    return future;
  }
}
