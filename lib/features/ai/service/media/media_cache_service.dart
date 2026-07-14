/// Persistent cache for remote AI media URLs.
///
/// The chat UI can receive images, videos, and audio as network URLs. This
/// service stores the first successful response under `~/.openhand/cache/media`
/// with a JSON sidecar so the cache remains traceable, measurable, and
/// cleanable from Settings → App Data.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/bounded_delete.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/lifecycle_cache.dart';

enum MediaCacheKind { image, video, audio }

class MediaCacheStats {
  const MediaCacheStats({required this.bytes, required this.fileCount});

  final int bytes;
  final int fileCount;

  static const MediaCacheStats empty = MediaCacheStats(bytes: 0, fileCount: 0);

  MediaCacheStats operator +(MediaCacheStats other) {
    return MediaCacheStats(
      bytes: bytes + other.bytes,
      fileCount: fileCount + other.fileCount,
    );
  }
}

class MediaCacheService {
  MediaCacheService._({
    String Function()? cacheDirectoryPathProvider,
    HttpClient Function(Duration connectionTimeout)? createHttpClient,
    int validatedPathCacheMaxEntries = _validatedPathCacheMaxEntries,
  }) : _validatedCachePaths = LifecycleLruCache<bool>(
         maxEntries: validatedPathCacheMaxEntries,
       ),
       _cacheDirectoryPathProvider =
           cacheDirectoryPathProvider ??
           OpenHandPaths.defaultMediaCacheDirectoryPath,
       _createHttpClient =
           createHttpClient ??
           ((connectionTimeout) => SystemProxyResolver.instance
               .createRawHttpClient(connectionTimeout: connectionTimeout));

  @visibleForTesting
  MediaCacheService.forTesting({
    required String cacheDirectoryPath,
    HttpClient Function(Duration connectionTimeout)? createHttpClient,
    int validatedPathCacheMaxEntries = _validatedPathCacheMaxEntries,
  }) : this._(
         cacheDirectoryPathProvider: () => cacheDirectoryPath,
         createHttpClient: createHttpClient,
         validatedPathCacheMaxEntries: validatedPathCacheMaxEntries,
       );

  static final MediaCacheService instance = MediaCacheService._();

  static const Duration _requestOpenTimeout = Duration(seconds: 20);
  static const Duration _responseHeaderTimeout = Duration(seconds: 30);
  static const Duration _responseChunkTimeout = Duration(seconds: 30);
  static const Duration _fileOperationTimeout = Duration(seconds: 30);
  static const Duration _cleanupTimeout = Duration(seconds: 5);
  static const Duration _cacheScanTimeout = Duration(seconds: 15);
  static const int _maxCacheScanEntries = 100000;
  static const BoundedDeletePolicy _cacheDeletePolicy = BoundedDeletePolicy(
    maxEntries: _maxCacheScanEntries + 1,
    maxDepth: 16,
    directoryIdleTimeout: _cleanupTimeout,
    operationTimeout: _cleanupTimeout,
    totalTimeout: _cacheScanTimeout,
  );
  static const Duration _imageDownloadDeadline = Duration(minutes: 5);
  static const Duration _audioDownloadDeadline = Duration(minutes: 8);
  static const Duration _videoDownloadDeadline = Duration(minutes: 20);
  static const int _maxImageCacheBytes = 64 * kBytesPerMiB;
  static const int _maxAudioCacheBytes = 512 * kBytesPerMiB;
  static const int _maxVideoCacheBytes = 2 * kBytesPerGiB;
  static const int _validatedPathCacheMaxEntries = 2048;

  static const Set<String> _imageExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.svg',
  };
  static const Set<String> _videoExtensions = <String>{
    '.mp4',
    '.webm',
    '.mov',
    '.m4v',
    '.mkv',
  };
  static const Set<String> _audioExtensions = <String>{
    '.mp3',
    '.wav',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.flac',
  };

  final Map<String, Future<String?>> _inflight = <String, Future<String?>>{};
  final LifecycleLruCache<bool> _validatedCachePaths;
  final String Function() _cacheDirectoryPathProvider;
  final HttpClient Function(Duration connectionTimeout) _createHttpClient;
  Directory? _cacheDir;

  static String get cacheDirectoryPath =>
      OpenHandPaths.defaultMediaCacheDirectoryPath();

  static String get legacyInlineMediaDirectoryPath =>
      p.join(Directory.systemTemp.path, 'openhand_media');

  Future<Directory> _ensureCacheDir() async {
    final existing = _cacheDir;
    if (existing != null &&
        await existing.exists().timeout(_fileOperationTimeout)) {
      return existing;
    }
    final dir = Directory(_cacheDirectoryPathProvider());
    await dir.create(recursive: true).timeout(_fileOperationTimeout);
    _cacheDir = dir;
    return dir;
  }

  /// Returns a cache path already validated by an asynchronous cache operation.
  /// This synchronous hot-path query performs no filesystem I/O.
  String? cachedPathForUrl(String url, {MediaCacheKind? kind}) {
    final uri = _httpUriOrNull(url);
    if (uri == null) return null;
    final path = _cacheFilePathForUrl(
      uri.toString(),
      _cacheDirectoryPathProvider(),
      kind,
    );
    return _validatedCachePaths.get(path) == true ? path : null;
  }

  /// Ensures [url] has a local cached copy and returns the file path. Failures
  /// are logged and returned as null so callers can fall back to the original
  /// network URL without breaking playback.
  Future<String?> ensureCached(String url, {MediaCacheKind? kind}) async {
    String? ownedCacheKey;
    Future<String?>? ownedFuture;
    try {
      final uri = _httpUriOrNull(url);
      if (uri == null) return null;
      final normalizedUrl = uri.toString();
      final cached = await _validatedCachedPath(normalizedUrl, kind: kind);
      if (cached != null) return cached;
      final cacheKey = _inflightKey(normalizedUrl, kind);
      final active = _inflight[cacheKey];
      if (active != null) return await active;
      final future = _downloadAndCache(uri, kind: kind);
      _inflight[cacheKey] = future;
      ownedCacheKey = cacheKey;
      ownedFuture = future;
      return await future;
    } catch (error, stack) {
      silentLog('media_cache', 'ensure cached media', error, stack);
      return null;
    } finally {
      if (ownedCacheKey != null &&
          identical(_inflight[ownedCacheKey], ownedFuture)) {
        _inflight.remove(ownedCacheKey);
      }
    }
  }

  /// Starts a best-effort background cache job. UI callers should not await it.
  void cacheInBackground(String url, {MediaCacheKind? kind}) {
    final uri = _httpUriOrNull(url);
    if (uri == null) return;
    unawaited(_cacheSafelyInBackground(uri.toString(), kind: kind));
  }

  Future<void> _cacheSafelyInBackground(
    String url, {
    MediaCacheKind? kind,
  }) async {
    try {
      await ensureCached(url, kind: kind);
    } catch (error, stack) {
      silentLog('media_cache', 'background cache', error, stack);
    }
  }

  /// Imports an already downloaded local file into the deterministic cache.
  /// This is used after an explicit "Save As" download so the app does not
  /// fetch the same remote media twice just to warm the cache.
  Future<String?> importFile(
    String url,
    String sourcePath, {
    MediaCacheKind? kind,
    String? mimeType,
  }) async {
    final uri = _httpUriOrNull(url);
    final normalizedSourcePath = nullIfBlank(sourcePath);
    if (uri == null || normalizedSourcePath == null) return null;
    final sourceFile = File(normalizedSourcePath);
    if (!await _looksUsableFile(sourceFile)) return null;
    final normalizedUrl = uri.toString();
    final cacheKind = kind ?? _kindFromUrl(normalizedUrl);
    final maxBytes = _maxBytesForKind(cacheKind);
    final bytes = await sourceFile.length();
    if (bytes <= 0 || bytes > maxBytes) return null;

    final dir = await _ensureCacheDir();
    final destPath = _cacheFilePathForUrl(normalizedUrl, dir.path, cacheKind);
    final destFile = File(destPath);
    if (!await _looksUsableFile(destFile)) {
      final tempFile = File('$destPath.part');
      try {
        await tempFile.parent.create(recursive: true);
        await sourceFile.copy(tempFile.path);
        if (await destFile.exists()) {
          await _deleteEntity(
            tempFile,
            'delete duplicate imported media temp file',
          );
        } else {
          await tempFile.rename(destPath);
        }
      } catch (error, stack) {
        silentLog('media_cache', 'import local file', error, stack);
        await _deleteEntity(tempFile, 'delete failed imported media temp file');
        return null;
      }
    }
    await _writeMetadata(
      mediaPath: destPath,
      url: normalizedUrl,
      kind: cacheKind,
      mimeType: mimeType,
      bytes: await File(destPath).length(),
    );
    _validatedCachePaths.put(destPath, true);
    return destPath;
  }

  Future<String?> _downloadAndCache(Uri uri, {MediaCacheKind? kind}) async {
    final normalizedUrl = uri.toString();
    final cacheKind = kind ?? _kindFromUrl(normalizedUrl);
    File? tempFile;
    HttpClient? client;
    try {
      final dir = await _ensureCacheDir();
      final destPath = _cacheFilePathForUrl(normalizedUrl, dir.path, cacheKind);
      tempFile = File('$destPath.part');
      final destFile = File(destPath);
      client = _createHttpClient(_requestOpenTimeout);
      final request = await client.getUrl(uri).timeout(_requestOpenTimeout);
      final response = await request.close().timeout(_responseHeaderTimeout);
      if (isHttpFailureStatus(response.statusCode)) {
        return null;
      }
      final contentType = response.headers.contentType;
      if (!_isCacheableContentType(contentType, cacheKind)) {
        return null;
      }
      final maxBytes = _maxBytesForKind(cacheKind);
      final declaredLength = response.contentLength;
      if (declaredLength > maxBytes) {
        return null;
      }

      await tempFile.parent
          .create(recursive: true)
          .timeout(_fileOperationTimeout);
      var written = 0;
      final downloadWatch = Stopwatch()..start();
      RandomAccessFile? output;
      try {
        final openedOutput = await tempFile
            .open(mode: FileMode.write)
            .timeout(_fileOperationTimeout);
        output = openedOutput;
        await for (final chunk in response.timeout(_responseChunkTimeout)) {
          if (downloadWatch.elapsed > _deadlineForKind(cacheKind)) {
            throw TimeoutException('Media cache download exceeded time limit.');
          }
          written += chunk.length;
          if (written > maxBytes) {
            throw FileSystemException(
              'Media cache download exceeded size limit.',
              normalizedUrl,
            );
          }
          await openedOutput.writeFrom(chunk).timeout(_fileOperationTimeout);
        }
        await openedOutput.flush().timeout(_fileOperationTimeout);
        await openedOutput.close().timeout(_cleanupTimeout);
        output = null;
      } finally {
        downloadWatch.stop();
        final pendingOutput = output;
        if (pendingOutput != null) {
          await _closeOutput(pendingOutput);
        }
      }
      if (written <= 0) {
        await _deleteEntity(tempFile, 'delete empty cached media temp file');
        return null;
      }

      if (await destFile.exists().timeout(_fileOperationTimeout)) {
        await _deleteEntity(
          tempFile,
          'delete duplicate cached media temp file',
        );
      } else {
        await tempFile.rename(destPath).timeout(_fileOperationTimeout);
      }
      final savedFile = File(destPath);
      if (!await _looksUsableFile(savedFile)) return null;
      await _writeMetadata(
        mediaPath: destPath,
        url: normalizedUrl,
        kind: cacheKind,
        mimeType: contentType?.mimeType,
        bytes: await savedFile.length().timeout(_fileOperationTimeout),
      );
      _validatedCachePaths.put(destPath, true);
      return destPath;
    } on TimeoutException catch (error, stack) {
      silentLog('media_cache', 'download timeout', error, stack);
      if (tempFile != null) {
        await _deleteEntity(
          tempFile,
          'delete timed-out cached media temp file',
        );
      }
      return null;
    } catch (error, stack) {
      silentLog('media_cache', 'download', error, stack);
      if (tempFile != null) {
        await _deleteEntity(tempFile, 'delete failed cached media temp file');
      }
      return null;
    } finally {
      try {
        client?.close(force: true);
      } catch (error, stack) {
        silentLog('media_cache', 'close download client', error, stack);
      }
    }
  }

  static Future<void> _closeOutput(RandomAccessFile output) async {
    try {
      await output.close().timeout(_cleanupTimeout);
    } catch (error, stack) {
      silentLog('media_cache', 'close cached media temp file', error, stack);
    }
  }

  Future<void> _writeMetadata({
    required String mediaPath,
    required String url,
    required MediaCacheKind? kind,
    required String? mimeType,
    required int bytes,
  }) async {
    final metadata = <String, Object?>{
      'version': 1,
      'source_url': url,
      'url_sha256': _cacheKey(url),
      'kind': kind?.name ?? _kindFromUrl(url)?.name,
      'mime_type': mimeType,
      'bytes': bytes,
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'media_path': mediaPath,
    };
    final sidecar = File(_metadataPathForMediaPath(mediaPath));
    try {
      await sidecar
          .writeAsString(prettyPrintJson(metadata), flush: true)
          .timeout(_fileOperationTimeout);
    } catch (error, stack) {
      silentLog('media_cache', 'write metadata', error, stack);
    }
  }

  static Future<MediaCacheStats> measureCache() async {
    final persistent = await _measureDirectory(Directory(cacheDirectoryPath));
    final legacy = await _measureDirectory(
      Directory(legacyInlineMediaDirectoryPath),
    );
    return persistent + legacy;
  }

  static Future<int> totalCacheBytes() async {
    return (await measureCache()).bytes;
  }

  static Future<void> clearCache() async {
    instance._validatedCachePaths.clear();
    await Future.wait(<Future<void>>[
      _clearDirectoryContents(Directory(cacheDirectoryPath)),
      _clearDirectoryContents(Directory(legacyInlineMediaDirectoryPath)),
    ]);
  }

  static Future<MediaCacheStats> _measureDirectory(Directory dir) async {
    if (!await dir.exists()) return MediaCacheStats.empty;
    try {
      final usage = await measureDirectoryBounded(
        dir,
        maxEntries: _maxCacheScanEntries,
        totalTimeout: _cacheScanTimeout,
        operationTimeout: _cleanupTimeout,
      );
      return MediaCacheStats(
        bytes: usage.totalBytes,
        fileCount: usage.fileCount,
      );
    } catch (error, stack) {
      silentLog('media_cache', 'list cache directory size', error, stack);
      return MediaCacheStats.empty;
    }
  }

  static Future<void> _clearDirectoryContents(Directory dir) async {
    try {
      await deletePathBounded(p.absolute(dir.path), policy: _cacheDeletePolicy);
    } catch (error, stack) {
      silentLog('media_cache', 'clear cache directory', error, stack);
    }
  }

  static Future<void> _deleteEntity(
    FileSystemEntity entity,
    String where,
  ) async {
    try {
      await deletePathBounded(
        p.absolute(entity.path),
        policy: _cacheDeletePolicy,
      );
    } catch (error, stack) {
      silentLog('media_cache', where, error, stack);
    }
  }

  static Uri? _httpUriOrNull(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https' ? uri : null;
  }

  static String _cacheKey(String url) =>
      sha256.convert(utf8.encode(url)).toString();

  static String _inflightKey(String url, MediaCacheKind? kind) {
    return '${kind?.name ?? 'media'}:${_cacheKey(url)}';
  }

  static String _cacheFilePathForUrl(
    String url,
    String dir,
    MediaCacheKind? kind,
  ) {
    final hash = _cacheKey(url).substring(0, 32);
    final ext = _extensionFromUrl(url, kind);
    final prefix = kind?.name ?? 'media';
    return p.join(dir, '$prefix-$hash$ext');
  }

  static String _metadataPathForMediaPath(String mediaPath) {
    final ext = p.extension(mediaPath);
    final stem = ext.isEmpty
        ? mediaPath
        : mediaPath.substring(0, mediaPath.length - ext.length);
    return '$stem.json';
  }

  Future<String?> _validatedCachedPath(
    String url, {
    MediaCacheKind? kind,
  }) async {
    final path = _cacheFilePathForUrl(url, _cacheDirectoryPathProvider(), kind);
    if (_validatedCachePaths.get(path) == true) return path;
    if (await _looksUsableFile(File(path))) {
      _validatedCachePaths.put(path, true);
      return path;
    }
    _validatedCachePaths.remove(path);
    await _deleteInvalidCachePair(path);
    return null;
  }

  static Future<bool> _looksUsableFile(File file) async {
    try {
      final type = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      ).timeout(_fileOperationTimeout);
      if (type != FileSystemEntityType.file) return false;
      return (await file.stat().timeout(_fileOperationTimeout)).size > 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _deleteInvalidCachePair(String mediaPath) async {
    try {
      final file = File(mediaPath);
      if (await file.exists().timeout(_cleanupTimeout)) {
        await file.delete().timeout(_cleanupTimeout);
      }
    } catch (error, stack) {
      silentLog('media_cache', 'delete invalid cached media', error, stack);
    }
    try {
      final sidecar = File(_metadataPathForMediaPath(mediaPath));
      if (await sidecar.exists().timeout(_cleanupTimeout)) {
        await sidecar.delete().timeout(_cleanupTimeout);
      }
    } catch (error, stack) {
      silentLog(
        'media_cache',
        'delete invalid cached media metadata',
        error,
        stack,
      );
    }
  }

  static bool _isCacheableContentType(
    ContentType? contentType,
    MediaCacheKind? kind,
  ) {
    if (contentType == null) return true;
    final primary = contentType.primaryType.toLowerCase();
    if (primary == 'image') return kind == null || kind == MediaCacheKind.image;
    if (primary == 'video') return kind == null || kind == MediaCacheKind.video;
    if (primary == 'audio') return kind == null || kind == MediaCacheKind.audio;
    return contentType.mimeType == 'application/octet-stream';
  }

  static int _maxBytesForKind(MediaCacheKind? kind) {
    return switch (kind) {
      MediaCacheKind.image => _maxImageCacheBytes,
      MediaCacheKind.video => _maxVideoCacheBytes,
      MediaCacheKind.audio => _maxAudioCacheBytes,
      null => _maxVideoCacheBytes,
    };
  }

  static Duration _deadlineForKind(MediaCacheKind? kind) {
    return switch (kind) {
      MediaCacheKind.image => _imageDownloadDeadline,
      MediaCacheKind.video => _videoDownloadDeadline,
      MediaCacheKind.audio => _audioDownloadDeadline,
      null => _videoDownloadDeadline,
    };
  }

  static MediaCacheKind? _kindFromUrl(String url) {
    final ext = _extensionFromUrl(url, null);
    if (_imageExtensions.contains(ext)) return MediaCacheKind.image;
    if (_videoExtensions.contains(ext)) return MediaCacheKind.video;
    if (_audioExtensions.contains(ext)) return MediaCacheKind.audio;
    return null;
  }

  static String _extensionFromUrl(String url, MediaCacheKind? kind) {
    try {
      final uri = Uri.parse(url);
      final ext = p.extension(uri.path).toLowerCase();
      if (_isAllowedExtensionForKind(ext, kind)) return ext;
    } catch (error, stack) {
      silentLog('media_cache', 'parse url extension', error, stack);
    }
    return switch (kind) {
      MediaCacheKind.image => '.png',
      MediaCacheKind.video => '.mp4',
      MediaCacheKind.audio => '.mp3',
      null => '.bin',
    };
  }

  static bool _isAllowedExtensionForKind(String ext, MediaCacheKind? kind) {
    if (ext.isEmpty || ext.length > 8) return false;
    return switch (kind) {
      MediaCacheKind.image => _imageExtensions.contains(ext),
      MediaCacheKind.video => _videoExtensions.contains(ext),
      MediaCacheKind.audio => _audioExtensions.contains(ext),
      null =>
        _imageExtensions.contains(ext) ||
            _videoExtensions.contains(ext) ||
            _audioExtensions.contains(ext),
    };
  }
}
