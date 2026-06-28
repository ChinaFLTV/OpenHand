// 2026-05-13 — 应用更新检查服务。抽象数据源层以便日后迁移到其他平台。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/version_compare.dart';
import 'silent_log.dart';

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
  GitHubReleaseDataSource({this.owner = 'ChinaFLTV', this.repo = 'OpenHand'});

  final String owner;
  final String repo;

  String get _apiUrl =>
      'https://api.github.com/repos/$owner/$repo/releases/latest';

  @override
  Future<AppUpdateCheckResult> checkForUpdate(String currentVersion) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(_apiUrl));
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'OpenHand-UpdateChecker');
      final response = await request.close();
      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        return AppUpdateCheckError(
          message: 'HTTP ${response.statusCode}: $body',
        );
      }
      final body = await response.transform(utf8.decoder).join();
      final release = parseGitHubReleaseInfo(
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
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(release.downloadUrl));
      request.headers.set('User-Agent', 'OpenHand-UpdateChecker');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed: HTTP ${response.statusCode}',
          uri: Uri.parse(release.downloadUrl),
        );
      }
      final contentLength = response.contentLength;
      final tempDir = Directory.systemTemp;
      final downloadUri = Uri.parse(release.downloadUrl);
      final parsedFileName = downloadUri.pathSegments.isEmpty
          ? 'openhand-update'
          : downloadUri.pathSegments.last.trim();
      final fileName = parsedFileName.isEmpty
          ? 'openhand-update'
          : parsedFileName;
      final filePath = p.join(tempDir.path, fileName);
      final file = File(filePath);
      final sink = file.openWrite();
      try {
        var received = 0;
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (contentLength > 0) {
            onProgress((received / contentLength).clamp(0.0, 1.0));
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      onFilePath(filePath);
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

@visibleForTesting
AppReleaseInfo? parseGitHubReleaseInfo(
  Object? raw, {
  String platformAssetSuffix = '',
}) {
  final json = stringKeyedMapFromValue(raw);
  final tagName = stringFromValue(json['tag_name']);
  if (tagName.isEmpty) return null;
  final suffix = platformAssetSuffix.trim().toLowerCase();
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
      final name = stringFromValue(asset['name']).toLowerCase();
      if (name.contains(platformAssetSuffix)) return asset;
    }
  }
  return assets.first;
}
