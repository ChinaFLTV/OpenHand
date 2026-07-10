// 2026-05-13 — 应用更新检查服务。抽象数据源层以便日后迁移到其他平台。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../shared/net/http_response_utils.dart';
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
const String _kGitHubReleaseAcceptHeader = 'application/vnd.github.v3+json';
const String _kUpdateCheckerUserAgent = 'OpenHand-UpdateChecker';
const String _kFallbackUpdateFileName = 'openhand-update';

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
      final request = await client
          .getUrl(Uri.parse(_apiUrl))
          .timeout(_kUpdateCheckConnectionTimeout);
      request.headers.set('Accept', _kGitHubReleaseAcceptHeader);
      request.headers.set('User-Agent', _kUpdateCheckerUserAgent);
      final response = await request.close().timeout(
        _kUpdateResponseHeaderTimeout,
      );
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
  }) async {
    if (release.downloadUrl.isEmpty) {
      throw Exception('No download URL available.');
    }
    final downloadUri = Uri.tryParse(release.downloadUrl);
    if (downloadUri == null ||
        downloadUri.scheme.toLowerCase() != 'https' ||
        downloadUri.host.trim().isEmpty ||
        downloadUri.userInfo.isNotEmpty) {
      throw const FormatException('Update download URL must use HTTPS.');
    }
    if (release.downloadSize > _kUpdateMaxDownloadBytes) {
      throw const FileSystemException('Update package is too large.');
    }
    final client = _createHttpClient(_kUpdateDownloadConnectionTimeout);
    Directory? downloadDirectory;
    try {
      final request = await client
          .getUrl(downloadUri)
          .timeout(_kUpdateDownloadConnectionTimeout);
      request.headers.set('User-Agent', _kUpdateCheckerUserAgent);
      final response = await request.close().timeout(
        _kUpdateResponseHeaderTimeout,
      );
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
      final fileName = _safeUpdateFileName(downloadUri);
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
            await directory.delete(recursive: true);
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
      client.close(force: true);
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
