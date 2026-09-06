// 应用更新检查服务。
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../shared/net/bounded_http_request.dart';
import '../../shared/net/http_redirect_utils.dart';
import '../../shared/net/http_response_utils.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_delete.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/bounded_json_conversion.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/duration_bounds.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/path_safety.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/user_failure_message.dart';
import '../../shared/util/version_compare.dart';
import 'silent_log.dart';
import 'system_proxy.dart';

const Duration _kUpdateCheckConnectionTimeout = Duration(seconds: 15);
const Duration _kUpdateDownloadConnectionTimeout = Duration(seconds: 30);
const Duration _kUpdateResponseHeaderTimeout = Duration(seconds: 30);
const Duration _kUpdateResponseIdleTimeout = Duration(seconds: 30);
const Duration _kUpdateCheckTotalTimeout = Duration(seconds: 45);
const Duration _kUpdateDownloadTotalTimeout = Duration(minutes: 30);
const Duration _kUpdateFileIoTimeout = Duration(seconds: 30);
const int _kUpdateMetadataMaxBytes = 2 * kBytesPerMiB;
const BoundedJsonConversionConfig _kUpdateMetadataJsonConversionConfig =
    kOpenHandCompactJsonConversionConfig;
const int _kUpdateMaxDownloadBytes = 2 * kBytesPerGiB;
const int _kUpdateMaxReleaseAssets = 256;
const int _kUpdateTagMaxCharacters = 128;
const int _kUpdateAssetNameMaxCharacters = 512;
const int _kUpdateReleaseNameMaxCharacters = 256;
const int _kUpdateReleaseNotesMaxCharacters = 64 * kBytesPerKiB;
const int _kUpdateDownloadUrlMaxCharacters = 8 * kBytesPerKiB;
const int _kUpdateMaxRedirects = 5;
const Duration _kUpdateRedirectDrainTimeout = Duration(seconds: 2);
const String _kGitHubReleaseAcceptHeader = kGitHubApiV3AcceptHeader;
const String _kUpdateCheckerUserAgent = 'OpenHand-UpdateChecker';
const String _kFallbackUpdateFileName = 'openhand-update';
final RegExp _kSha256HexPattern = RegExp(r'^[0-9a-f]{64}$');
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
    this.downloadSha256 = '',
    this.isPreRelease = false,
  });

  final String version;
  final String tagName;
  final String releaseName;
  final String releaseNotes;
  final DateTime publishedAt;
  final String downloadUrl;
  final int downloadSize;
  final String downloadSha256;
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
    final deadline = MonotonicDeadline(
      _kUpdateCheckTotalTimeout,
      timeoutMessage: '更新检查超过总时限。',
    );
    Duration remainingBudget() => deadline.remaining();
    try {
      final result = await _getFollowingSecureRedirects(
        client: client,
        initialUri: Uri.parse(_apiUrl),
        connectionTimeout: _kUpdateCheckConnectionTimeout,
        remainingBudget: remainingBudget,
        headers: const <String, String>{
          kAcceptHeaderName: _kGitHubReleaseAcceptHeader,
          kUserAgentHeaderName: _kUpdateCheckerUserAgent,
        },
      );
      final response = result.response;
      final body = await readBoundedHttpResponseText(
        response,
        maxBytes: _kUpdateMetadataMaxBytes,
        idleTimeout: _kUpdateResponseIdleTimeout,
        totalTimeout: remainingBudget(),
        allowMalformed: true,
      );
      if (response.statusCode != HttpStatus.ok) {
        return AppUpdateCheckError(
          message: '更新服务返回 HTTP ${response.statusCode}。',
        );
      }
      final release = _parseGitHubReleaseInfo(
        decodeJsonTextUsingConfig(
          body,
          maxTextCodeUnits: _kUpdateMetadataMaxBytes,
          config: _kUpdateMetadataJsonConversionConfig,
        ),
        platformAssetSuffix: _platformAssetSuffix(),
      );
      if (release == null) {
        return AppUpdateCheckError(message: '无法解析版本发布信息。');
      }
      if (release.isNewerThan(currentVersion)) {
        return AppUpdateAvailable(release: release);
      }
      return AppUpdateNotAvailable();
    } catch (error, stack) {
      silentLog('app_update_checker', '检查应用更新', error, stack);
      return AppUpdateCheckError(
        message: userFailureMessage(error, fallback: '检查更新失败，请稍后重试。'),
      );
    } finally {
      deadline.stop();
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
      throw Exception('没有可用的更新包下载地址。');
    }
    final initialDownloadUri = Uri.tryParse(release.downloadUrl);
    if (initialDownloadUri == null) {
      throw const FormatException('更新包下载地址必须使用 HTTPS。');
    }
    _validateSecureUpdateUri(initialDownloadUri);
    if (release.downloadSize > _kUpdateMaxDownloadBytes) {
      throw const FileSystemException('更新包超过大小上限。');
    }
    final expectedSha256 = release.downloadSha256.trim().toLowerCase();
    if (expectedSha256.isNotEmpty &&
        !_kSha256HexPattern.hasMatch(expectedSha256)) {
      throw const FormatException('更新包 SHA-256 摘要格式无效。');
    }
    final client = _createHttpClient(_kUpdateDownloadConnectionTimeout);
    final deadline = MonotonicDeadline(
      _kUpdateDownloadTotalTimeout,
      timeoutMessage: '更新包下载超过总时限。',
    );
    Duration remainingBudget() => deadline.remaining();
    var finished = false;
    var cancelled = false;
    void cancelDownload() {
      cancelled = true;
      if (!finished) client.close(force: true);
    }

    if (cancelSignal != null) {
      unawaited(
        cancelSignal.then<void>(
          (_) => cancelDownload(),
          onError: (Object _, StackTrace _) => cancelDownload(),
        ),
      );
    }
    Directory? downloadDirectory;
    try {
      final result = await _getFollowingSecureRedirects(
        client: client,
        initialUri: initialDownloadUri,
        connectionTimeout: _kUpdateDownloadConnectionTimeout,
        remainingBudget: remainingBudget,
        headers: const <String, String>{
          kUserAgentHeaderName: _kUpdateCheckerUserAgent,
        },
      );
      final response = result.response;
      final downloadUri = result.uri;
      if (response.statusCode != HttpStatus.ok) {
        await readBoundedHttpResponseText(
          response,
          maxBytes: _kUpdateMetadataMaxBytes,
          idleTimeout: _kUpdateResponseIdleTimeout,
          totalTimeout: remainingBudget(),
          allowMalformed: true,
        );
        throw HttpException(
          '更新包下载失败：HTTP ${response.statusCode}。',
          uri: downloadUri,
        );
      }
      final contentLength = response.contentLength;
      if (contentLength > _kUpdateMaxDownloadBytes) {
        throw const FileSystemException('更新包超过大小上限。');
      }
      if (contentLength > 0 &&
          release.downloadSize > 0 &&
          contentLength != release.downloadSize) {
        throw const FileSystemException('更新包大小与发布信息不一致。');
      }
      final expectedLength = contentLength > 0
          ? contentLength
          : release.downloadSize;
      if (expectedLength <= 0) {
        throw const FileSystemException('无法确定更新包大小。');
      }
      downloadDirectory = await createTemporaryDirectoryBounded(
        prefix: 'openhand-update-',
        timeout: shorterDuration(_kUpdateFileIoTimeout, remainingBudget()),
        cleanupPolicy: _kUpdateCleanupPolicy,
        onSecondaryError: (error, stack) =>
            silentLog('app_update_checker', '清理延迟创建的更新目录', error, stack),
      );
      final fileName = _safeUpdateFileName(initialDownloadUri);
      final filePath = p.join(downloadDirectory.path, fileName);
      final partialFile = File('$filePath.part');
      BoundedRandomAccessFileLease? output;
      var deleteOnRelease = false;
      final checksumSink = expectedSha256.isEmpty ? null : _UpdateDigestSink();
      final checksumInput = checksumSink == null
          ? null
          : sha256.startChunkedConversion(checksumSink);
      var checksumInputClosed = false;
      try {
        final openedOutput = await openBoundedRandomAccessFileLease(
          partialFile,
          mode: FileMode.write,
          timeout: shorterDuration(_kUpdateFileIoTimeout, remainingBudget()),
          deleteIfOpenCompletesLate: true,
          release: (file) async {
            await file.close();
            if (deleteOnRelease &&
                await partialFile.exists().timeout(_kUpdateFileIoTimeout)) {
              await partialFile.delete().timeout(_kUpdateFileIoTimeout);
            }
          },
        );
        output = openedOutput;
        var received = 0;
        final boundedResponse = limitByteStream(
          response,
          maxBytes: _kUpdateMaxDownloadBytes,
          idleTimeout: _kUpdateResponseIdleTimeout,
          totalTimeout: remainingBudget(),
        );
        await for (final chunk in boundedResponse) {
          if (cancelled) {
            throw const HttpException('更新包下载已取消。');
          }
          if (chunk.length > expectedLength - received) {
            throw const FileSystemException('更新包大小与发布信息不一致。');
          }
          checksumInput?.add(chunk);
          await openedOutput.run(
            (file) => file.writeFrom(chunk),
            timeout: shorterDuration(_kUpdateFileIoTimeout, remainingBudget()),
          );
          received += chunk.length;
          onProgress(unitRatio(received, expectedLength));
        }
        if (cancelled) {
          throw const HttpException('更新包下载已取消。');
        }
        if (received <= 0) {
          throw const FileSystemException('下载的更新包为空。');
        }
        if (received != expectedLength) {
          throw const FileSystemException('更新包下载不完整。');
        }
        checksumInput?.close();
        checksumInputClosed = true;
        if (checksumSink != null &&
            checksumSink.digest.toString() != expectedSha256) {
          throw const FileSystemException('更新包 SHA-256 校验失败。');
        }
        await openedOutput.run(
          (file) => file.flush(),
          timeout: shorterDuration(_kUpdateFileIoTimeout, remainingBudget()),
        );
        await openedOutput.close(
          timeout: shorterDuration(_kUpdateFileIoTimeout, remainingBudget()),
        );
        output = null;
      } finally {
        if (!checksumInputClosed) checksumInput?.close();
        if (output != null) deleteOnRelease = true;
        await output?.cleanup();
      }
      if (cancelled) {
        throw const HttpException('更新包下载已取消。');
      }
      final publish = partialFile.rename(filePath);
      try {
        await publish.timeout(
          shorterDuration(_kUpdateFileIoTimeout, remainingBudget()),
        );
      } on TimeoutException {
        final directory = downloadDirectory;
        downloadDirectory = null;
        _cleanupLateUpdatePublish(publish, directory);
        rethrow;
      }
      if (cancelled) {
        throw const HttpException('更新包下载已取消。');
      }
      onProgress(1.0);
      onFilePath(filePath);
    } catch (_) {
      final directory = downloadDirectory;
      if (directory != null) {
        try {
          if (await directory.exists().timeout(_kUpdateFileIoTimeout)) {
            await deletePathBounded(
              p.absolute(directory.path),
              policy: _kUpdateCleanupPolicy,
            );
          }
        } catch (error, stack) {
          silentLog('app_update_checker', '清理下载失败的更新包', error, stack);
        }
      }
      rethrow;
    } finally {
      finished = true;
      deadline.stop();
      client.close(force: true);
    }
  }

  Future<({HttpClientResponse response, Uri uri})>
  _getFollowingSecureRedirects({
    required HttpClient client,
    required Uri initialUri,
    required Duration connectionTimeout,
    required Duration Function() remainingBudget,
    required Map<String, String> headers,
  }) async {
    var uri = initialUri;
    for (var redirects = 0; ; redirects += 1) {
      _validateSecureUpdateUri(uri);
      final request = await openHttpClientRequestBounded(
        () => client.getUrl(uri),
        timeout: shorterDuration(connectionTimeout, remainingBudget()),
        timeoutMessage: '更新请求打开超时。',
      );
      request
        ..followRedirects = false
        ..maxRedirects = 0;
      for (final header in headers.entries) {
        request.headers.set(header.key, header.value);
      }
      final response = await closeHttpClientRequestBounded(
        request,
        timeout: shorterDuration(
          _kUpdateResponseHeaderTimeout,
          remainingBudget(),
        ),
        timeoutMessage: '更新请求响应头获取超时。',
      );
      if (!isRedirectStatusCode(response.statusCode)) {
        return (response: response, uri: uri);
      }
      if (redirects >= _kUpdateMaxRedirects) {
        throw HttpException('更新请求超过重定向次数上限。', uri: uri);
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.trim().isEmpty) {
        throw HttpException('更新请求的重定向缺少 Location。', uri: uri);
      }
      final nextUri = uri.resolve(location.trim());
      _validateSecureUpdateUri(nextUri);
      final remaining = remainingBudget();
      await drainByteStreamWithTimeout(
        response,
        idleTimeout: shorterDuration(_kUpdateRedirectDrainTimeout, remaining),
        totalTimeout: remaining,
      );
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
    throw const FormatException('更新地址必须使用 HTTPS。');
  }
}

String _safeUpdateFileName(Uri uri) {
  final rawName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last.trim();
  final basename = nullIfBlank(p.basename(rawName));
  return sanitizePortableFileNamePart(
    basename ?? '',
    fallback: _kFallbackUpdateFileName,
    allowWhitespace: true,
    collapseReplacement: true,
  );
}

void _cleanupLateUpdatePublish(Future<File> publish, Directory directory) {
  unawaited(
    publish
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() async {
          try {
            await deletePathBounded(
              p.absolute(directory.path),
              policy: _kUpdateCleanupPolicy,
            );
          } catch (error, stack) {
            silentLog('app_update_checker', '清理延迟发布的更新包', error, stack);
          }
        }),
  );
}

AppReleaseInfo? _parseGitHubReleaseInfo(
  Object? raw, {
  String platformAssetSuffix = '',
}) {
  final json = stringKeyedMapFromValue(raw);
  final tagName = stringFromValue(json['tag_name']);
  if (tagName.isEmpty || tagName.length > _kUpdateTagMaxCharacters) {
    return null;
  }
  final publishedAt = dateTimeFromValue(json['published_at']);
  if (publishedAt == null) return null;
  final suffix = lowercaseStringFromValue(platformAssetSuffix);
  final version = tagName.replaceFirst(RegExp('^v'), '');
  if (version.isEmpty) return null;
  final selectedAsset = _selectReleaseAsset(json['assets'], suffix);
  final releaseName = stringFromValue(json['name'], fallback: tagName);
  final releaseNotes = stringFromValue(json['body']);
  return AppReleaseInfo(
    version: version,
    tagName: tagName,
    releaseName: clipTextByCodeUnits(
      releaseName,
      _kUpdateReleaseNameMaxCharacters,
      suffix: '…',
    ),
    releaseNotes: clipTextByCodeUnits(
      releaseNotes,
      _kUpdateReleaseNotesMaxCharacters,
      suffix: '\n…',
    ),
    publishedAt: publishedAt.toLocal(),
    downloadUrl: _secureUpdateDownloadUrl(
      selectedAsset?['browser_download_url'],
    ),
    downloadSize: nonNegativeIntFromValue(selectedAsset?['size'], fallback: 0),
    downloadSha256: _releaseAssetSha256(selectedAsset),
    isPreRelease: boolFromValue(json['prerelease']),
  );
}

String _releaseAssetSha256(Map<String, Object?>? asset) {
  const prefix = 'sha256:';
  final value = stringFromValue(asset?['digest']).trim().toLowerCase();
  if (value.isEmpty) return '';
  if (!value.startsWith(prefix)) {
    throw const FormatException('更新包 SHA-256 摘要格式无效。');
  }
  final checksum = value.substring(prefix.length);
  if (!_kSha256HexPattern.hasMatch(checksum)) {
    throw const FormatException('更新包 SHA-256 摘要格式无效。');
  }
  return checksum;
}

final class _UpdateDigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get digest => _digest ?? (throw StateError('更新包摘要尚未生成。'));

  @override
  void add(Digest data) {
    if (_digest != null) throw StateError('更新包摘要被重复写入。');
    _digest = data;
  }

  @override
  void close() {}
}

Map<String, Object?>? _selectReleaseAsset(
  Object? rawAssets,
  String platformAssetSuffix,
) {
  if (rawAssets is! List) return null;
  Map<String, Object?>? firstAsset;
  var scanned = 0;
  for (final rawAsset in rawAssets) {
    if (scanned >= _kUpdateMaxReleaseAssets) break;
    scanned += 1;
    if (rawAsset is! Map) continue;
    final asset = stringKeyedMapFromValue(rawAsset);
    firstAsset ??= asset;
    if (platformAssetSuffix.isEmpty) continue;
    final rawName = stringFromValue(asset['name']);
    if (rawName.length > _kUpdateAssetNameMaxCharacters) continue;
    final name = rawName.toLowerCase();
    if (name.contains(platformAssetSuffix)) return asset;
  }
  return platformAssetSuffix.isEmpty ? firstAsset : null;
}

String _secureUpdateDownloadUrl(Object? raw) {
  final value = stringFromValue(raw).trim();
  if (value.isEmpty || value.length > _kUpdateDownloadUrlMaxCharacters) {
    return '';
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return '';
  try {
    _validateSecureUpdateUri(uri);
    return uri.toString();
  } on FormatException {
    return '';
  }
}
