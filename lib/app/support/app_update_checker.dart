// 应用更新检查服务。抽象数据源层以便日后迁移到其他平台。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../shared/net/http_redirect_utils.dart';
import '../../shared/net/http_response_utils.dart';
import '../../shared/util/bounded_delete.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/version_compare.dart';
import 'silent_log.dart';
import 'system_proxy.dart';

const Duration _kUpdateCheckConnectionTimeout = Duration(seconds: 15);
const Duration _kUpdateDownloadConnectionTimeout = Duration(seconds: 30);
const Duration _kUpdateResponseHeaderTimeout = Duration(seconds: 30);
const Duration _kUpdateResponseIdleTimeout = Duration(seconds: 30);
const Duration _kUpdateCheckTotalTimeout = Duration(seconds: 45);
const Duration _kUpdateDownloadTotalTimeout = Duration(minutes: 30);
const int _kUpdateMetadataMaxBytes = 2 * 1024 * 1024;
const int _kUpdateMaxDownloadBytes = 2 * 1024 * 1024 * 1024;
const int _kUpdateMaxRedirects = 5;
const Duration _kUpdateRedirectDrainTimeout = Duration(seconds: 2);
const String _kGitHubReleaseAcceptHeader = 'application/vnd.github.v3+json';
const String _kUpdateCheckerUserAgent = 'OpenHand-UpdateChecker';
const String _kFallbackUpdateFileName = 'openhand-update';
const BoundedDeletePolicy _kUpdateCleanupPolicy = BoundedDeletePolicy(
  maxEntries: 16,
  maxDepth: 2,
  operationTimeout: Duration(seconds: 5),
  totalTimeout: Duration(seconds: 15),
);

/// 应用版本更新信息。
class AppReleaseInfo {
  const AppReleaseInfo({
    required this.version,
    required this.tagName,
    required this.releaseName,
    required this.releaseNotes,
    required this.publishedAt,
    required this.downloadUrl,
    required this.downloadSize,
    this.isPreRelease = false,
  });

  final String version;
  final String tagName;
  final String releaseName;
  final String releaseNotes;
  final DateTime publishedAt;
  final String downloadUrl;
  final int downloadSize;
  final bool isPreRelease;

  /// 比较版本号，返回 true 表示此版本比 [currentVersion] 更新。
  bool isNewerThan(String currentVersion) {
    return compareSemanticVersions(
          version,
          currentVersion,
          lexicalFallback: false,
        ) >
        0;
  }
}

/// 更新检查结果。
sealed class AppUpdateCheckResult {}

class AppUpdateAvailable extends AppUpdateCheckResult {
  AppUpdateAvailable({required this.release});
  final AppReleaseInfo release;
}

class AppUpdateNotAvailable extends AppUpdateCheckResult {}

class AppUpdateCheckError extends AppUpdateCheckResult {
  AppUpdateCheckError({required this.message});
  final String message;
}

/// 抽象更新数据源接口，便于日后替换为其他数据源实现。
abstract class AppUpdateDataSource {
  Future<AppUpdateCheckResult> checkForUpdate(String currentVersion);
  Future<void> downloadUpdate(
    AppReleaseInfo release, {
    required ValueChanged<double> onProgress,
    required ValueChanged<String> onFilePath,
    Future<void>? cancelSignal,
  });
}

/// GitHub Release 数据源实现。
class GitHubReleaseDataSource implements AppUpdateDataSource {
  GitHubReleaseDataSource({
    this.owner = 'ChinaFLTV',
    this.repo = 'OpenHand',
    SystemProxyResolver? proxyResolver,
  }) : _proxyResolver = proxyResolver ?? SystemProxyResolver.instance;

  final String owner;
  final String repo;
  final SystemProxyResolver _proxyResolver;

  String get _apiUrl =>
      'https://api.github.com/repos/$owner/$repo/releases/latest';

  HttpClient _createHttpClient(Duration connectionTimeout) {
    return _proxyResolver.createRawHttpClient(
      connectionTimeout: connectionTimeout,
    );
  }

  @override
  Future<AppUpdateCheckResult> checkForUpdate(String currentVersion) async {
    final client = _createHttpClient(_kUpdateCheckConnectionTimeout);
    try {
      final result = await _getFollowingSecureRedirects(
        client: client,
        initialUri: Uri.parse(_apiUrl),
        connectionTimeout: _kUpdateCheckConnectionTimeout,
        headers: const <String, String>{
          'Accept': _kGitHubReleaseAcceptHeader,
          'User-Agent': _kUpdateCheckerUserAgent,
        },
      );
      final response = result.response;
      final body = await readBoundedHttpResponseText(
        response,
        maxBytes: _kUpdateMetadataMaxBytes,
        idleTimeout: _kUpdateResponseIdleTimeout,
        totalTimeout: _kUpdateCheckTotalTimeout,
        allowMalformed: true,
      );
      if (response.statusCode != 200) {
        return AppUpdateCheckError(
          message: 'HTTP ${response.statusCode}: $body',
        );
      }
      final release = _parseGitHubReleaseInfo(
        jsonDecode(body),
        platformAssetSuffix: _platformAssetSuffix(),
      );
      if (release == null) {
        return AppUpdateCheckError(message: 'Failed to parse release info.');
      }
      if (release.isNewerThan(currentVersion)) {
        return AppUpdateAvailable(release: release);
      }
      return AppUpdateNotAvailable();
    } catch (error, stack) {
      silentLog('app_update_checker', 'checkForUpdate', error, stack);
      return AppUpdateCheckError(message: '$error');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> downloadUpdate(
    AppReleaseInfo release, {
    required ValueChanged<double> onProgress,
    required ValueChanged<String> onFilePath,
    Future<void>? cancelSignal,
  }) async {
    if (release.downloadUrl.isEmpty) {
      throw Exception('No download URL available.');
    }
    final initialDownloadUri = Uri.tryParse(release.downloadUrl);
    if (initialDownloadUri == null) {
      throw const FormatException('Update download URL must use HTTPS.');
    }
    _validateSecureUpdateUri(initialDownloadUri);
    if (release.downloadSize > _kUpdateMaxDownloadBytes) {
      throw const FileSystemException('Update package is too large.');
    }
    final client = _createHttpClient(_kUpdateDownloadConnectionTimeout);
    var finished = false;
    if (cancelSignal != null) {
      unawaited(
        cancelSignal.then<void>(
          (_) {
            if (!finished) client.close(force: true);
          },
          onError: (Object _, StackTrace _) {
            if (!finished) client.close(force: true);
          },
        ),
      );
    }
    Directory? downloadDirectory;
    try {
      final result = await _getFollowingSecureRedirects(
        client: client,
        initialUri: initialDownloadUri,
        connectionTimeout: _kUpdateDownloadConnectionTimeout,
        headers: const <String, String>{'User-Agent': _kUpdateCheckerUserAgent},
      );
      final response = result.response;
      final downloadUri = result.uri;
      if (response.statusCode != 200) {
        final body = await readBoundedHttpResponseText(
          response,
          maxBytes: _kUpdateMetadataMaxBytes,
          idleTimeout: _kUpdateResponseIdleTimeout,
          totalTimeout: _kUpdateCheckTotalTimeout,
          allowMalformed: true,
        );
        throw HttpException(
          'Download failed: HTTP ${response.statusCode}: $body',
          uri: downloadUri,
        );
      }
      final contentLength = response.contentLength;
      if (contentLength > _kUpdateMaxDownloadBytes) {
        throw const FileSystemException('Update package is too large.');
      }
      downloadDirectory = await Directory.systemTemp.createTemp(
        'openhand-update-',
      );
      final fileName = _safeUpdateFileName(initialDownloadUri);
      final filePath = p.join(downloadDirectory.path, fileName);
      final partialFile = File('$filePath.part');
      final sink = partialFile.openWrite();
      try {
        var received = 0;
        final deadline = DateTime.now().add(_kUpdateDownloadTotalTimeout);
        await for (final chunk in response.timeout(
          _kUpdateResponseIdleTimeout,
        )) {
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('Update download exceeded time limit.');
          }
          sink.add(chunk);
          received += chunk.length;
          if (received > _kUpdateMaxDownloadBytes) {
            throw const FileSystemException('Update package is too large.');
          }
          if (contentLength > 0) {
            onProgress(unitRatio(received, contentLength));
          }
        }
        if (received <= 0) {
          throw const FileSystemException('Downloaded update is empty.');
        }
        if (contentLength > 0 && received != contentLength) {
          throw const FileSystemException('Update download is incomplete.');
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      await partialFile.rename(filePath);
      onProgress(1.0);
      onFilePath(filePath);
    } catch (_) {
      final directory = downloadDirectory;
      if (directory != null) {
        try {
          if (await directory.exists()) {
            await deletePathBounded(
              p.absolute(directory.path),
              policy: _kUpdateCleanupPolicy,
            );
          }
        } catch (error, stack) {
          silentLog(
            'app_update_checker',
            'clean failed update download',
            error,
            stack,
          );
        }
      }
      rethrow;
    } finally {
      finished = true;
      client.close(force: true);
    }
  }

  Future<({HttpClientResponse response, Uri uri})>
  _getFollowingSecureRedirects({
    required HttpClient client,
    required Uri initialUri,
    required Duration connectionTimeout,
    required Map<String, String> headers,
  }) async {
    var uri = initialUri;
    for (var redirects = 0; ; redirects += 1) {
      _validateSecureUpdateUri(uri);
      final request = await client.getUrl(uri).timeout(connectionTimeout);
      request
        ..followRedirects = false
        ..maxRedirects = 0;
      for (final header in headers.entries) {
        request.headers.set(header.key, header.value);
      }
      final response = await request.close().timeout(
        _kUpdateResponseHeaderTimeout,
      );
      if (!isRedirectStatusCode(response.statusCode)) {
        return (response: response, uri: uri);
      }
      if (redirects >= _kUpdateMaxRedirects) {
        throw HttpException(
          'Update request exceeded redirect limit.',
          uri: uri,
        );
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.trim().isEmpty) {
        throw HttpException('Update redirect is missing Location.', uri: uri);
      }
      final nextUri = uri.resolve(location.trim());
      _validateSecureUpdateUri(nextUri);
      await response.drain<void>().timeout(_kUpdateRedirectDrainTimeout);
      uri = nextUri;
    }
  }

  String _platformAssetSuffix() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return '.exe';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return '.apk';
    if (Platform.isIOS) return '.ipa';
    return '';
  }
}

void _validateSecureUpdateUri(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https' ||
      uri.host.trim().isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Update URL must use HTTPS.');
  }
}

String _safeUpdateFileName(Uri uri) {
  final rawName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last.trim();
  final basename = nullIfBlank(p.basename(rawName));
  if (basename == null || basename == '.' || basename == '..') {
    return _kFallbackUpdateFileName;
  }
  return basename.replaceAll(RegExp(r'[\\/]'), '_');
}

AppReleaseInfo? _parseGitHubReleaseInfo(
  Object? raw, {
  String platformAssetSuffix = '',
}) {
  final json = stringKeyedMapFromValue(raw);
  final tagName = stringFromValue(json['tag_name']);
  if (tagName.isEmpty) return null;
  final suffix = lowercaseStringFromValue(platformAssetSuffix);
  final version = tagName.replaceFirst(RegExp(r'^v'), '');
  final assets = stringKeyedMapListFromValue(json['assets']);
  final selectedAsset = _selectReleaseAsset(assets, suffix);
  return AppReleaseInfo(
    version: version,
    tagName: tagName,
    releaseName: stringFromValue(json['name'], fallback: tagName),
    releaseNotes: stringFromValue(json['body']),
    publishedAt:
        dateTimeFromValue(json['published_at'])?.toLocal() ?? DateTime.now(),
    downloadUrl: stringFromValue(selectedAsset?['browser_download_url']),
    downloadSize: nonNegativeIntFromValue(selectedAsset?['size'], fallback: 0),
    isPreRelease: boolFromValue(json['prerelease']),
  );
}

Map<String, Object?>? _selectReleaseAsset(
  List<Map<String, Object?>> assets,
  String platformAssetSuffix,
) {
  if (assets.isEmpty) return null;
  if (platformAssetSuffix.isNotEmpty) {
    for (final asset in assets) {
      final name = lowercaseStringFromValue(asset['name']);
      if (name.contains(platformAssetSuffix)) return asset;
    }
  }
  return assets.first;
}
