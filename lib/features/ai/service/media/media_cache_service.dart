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
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';

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
  MediaCacheService._();

  static final MediaCacheService instance = MediaCacheService._();

  static const Duration _requestOpenTimeout = Duration(seconds: 20);
  static const Duration _responseHeaderTimeout = Duration(seconds: 30);
  static const Duration _responseChunkTimeout = Duration(seconds: 30);
  static const Duration _imageDownloadDeadline = Duration(minutes: 5);
  static const Duration _audioDownloadDeadline = Duration(minutes: 8);
  static const Duration _videoDownloadDeadline = Duration(minutes: 20);
  static const int _maxImageCacheBytes = 64 * kBytesPerMiB;
  static const int _maxAudioCacheBytes = 512 * kBytesPerMiB;
  static const int _maxVideoCacheBytes = 2 * kBytesPerGiB;

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
  Directory? _cacheDir;

  static String get cacheDirectoryPath =>
      OpenHandPaths.defaultMediaCacheDirectoryPath();

  static String get legacyInlineMediaDirectoryPath =>
      p.join(Directory.systemTemp.path, 'openhand_media');

  Future<Directory> _ensureCacheDir() async {
    final existing = _cacheDir;
    if (existing != null && await existing.exists()) {
      return existing;
    }
    final dir = Directory(cacheDirectoryPath);
    await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  /// Returns an existing valid cache file for [url], or null when the cache is
  /// missing / invalid. This method is synchronous because it is used inside
  /// hot widget build paths; it only probes a deterministic file path.
  String? cachedPathForUrl(String url, {MediaCacheKind? kind}) {
    final uri = _httpUriOrNull(url);
    if (uri == null) return null;
    final path = _cacheFilePathForUrl(uri.toString(), cacheDirectoryPath, kind);
    final file = File(path);
    if (!_looksUsableFile(file)) {
      _deleteInvalidCachePair(path);
      return null;
    }
    return path;
  }

  /// Ensures [url] has a local cached copy and returns the file path. Failures
  /// are logged and returned as null so callers can fall back to the original
  /// network URL without breaking playback.
  Future<String?> ensureCached(String url, {MediaCacheKind? kind}) async {
    final uri = _httpUriOrNull(url);
    if (uri == null) return null;
    final normalizedUrl = uri.toString();
    final cached = cachedPathForUrl(normalizedUrl, kind: kind);
    if (cached != null) return cached;
    final cacheKey = _inflightKey(normalizedUrl, kind);
    final active = _inflight[cacheKey];
    if (active != null) return active;
    final future = _downloadAndCache(uri, kind: kind);
    _inflight[cacheKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inflight[cacheKey], future)) {
        _inflight.remove(cacheKey);
      }
    }
  }

  /// Starts a best-effort background cache job. UI callers should not await it.
  void cacheInBackground(String url, {MediaCacheKind? kind}) {
    final uri = _httpUriOrNull(url);
    if (uri == null) return;
    if (cachedPathForUrl(uri.toString(), kind: kind) != null) return;
    unawaited(ensureCached(uri.toString(), kind: kind));
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
    if (!_looksUsableFile(sourceFile)) return null;
    final normalizedUrl = uri.toString();
    final cacheKind = kind ?? _kindFromUrl(normalizedUrl);
    final maxBytes = _maxBytesForKind(cacheKind);
    final bytes = await sourceFile.length();
    if (bytes <= 0 || bytes > maxBytes) return null;

    final dir = await _ensureCacheDir();
    final destPath = _cacheFilePathForUrl(normalizedUrl, dir.path, cacheKind);
    final destFile = File(destPath);
    if (!_looksUsableFile(destFile)) {
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
    return destPath;
  }

  Future<String?> _downloadAndCache(Uri uri, {MediaCacheKind? kind}) async {
    final normalizedUrl = uri.toString();
    final cacheKind = kind ?? _kindFromUrl(normalizedUrl);
    final dir = await _ensureCacheDir();
    final destPath = _cacheFilePathForUrl(normalizedUrl, dir.path, cacheKind);
    final tempPath = '$destPath.part';
    final tempFile = File(tempPath);
    final destFile = File(destPath);
    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: _requestOpenTimeout,
    );
    try {
      final request = await client.getUrl(uri).timeout(_requestOpenTimeout);
      final response = await request.close().timeout(_responseHeaderTimeout);
      if (isHttpFailureStatus(response.statusCode)) {
        await response.drain<void>();
        return null;
      }
      final contentType = response.headers.contentType;
      if (!_isCacheableContentType(contentType, cacheKind)) {
        await response.drain<void>();
        return null;
      }
      final maxBytes = _maxBytesForKind(cacheKind);
      final declaredLength = response.contentLength;
      if (declaredLength > maxBytes) {
        await response.drain<void>();
        return null;
      }

      await tempFile.parent.create(recursive: true);
      final sink = tempFile.openWrite();
      var written = 0;
      var outputClosed = false;
      final deadline = DateTime.now().add(_deadlineForKind(cacheKind));

      Future<void> closeOutput() async {
        if (outputClosed) return;
        outputClosed = true;
        await sink.close();
      }

      try {
        await for (final chunk in response.timeout(_responseChunkTimeout)) {
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('Media cache download exceeded time limit.');
          }
          written += chunk.length;
          if (written > maxBytes) {
            throw FileSystemException(
              'Media cache download exceeded size limit.',
              normalizedUrl,
            );
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await closeOutput();
      }
      if (written <= 0) {
        await _deleteEntity(tempFile, 'delete empty cached media temp file');
        return null;
      }

      if (await destFile.exists()) {
        await _deleteEntity(
          tempFile,
          'delete duplicate cached media temp file',
        );
      } else {
        await tempFile.rename(destPath);
      }
      final savedFile = File(destPath);
      if (!_looksUsableFile(savedFile)) return null;
      await _writeMetadata(
        mediaPath: destPath,
        url: normalizedUrl,
        kind: cacheKind,
        mimeType: contentType?.mimeType,
        bytes: await savedFile.length(),
      );
      return destPath;
    } on TimeoutException catch (error, stack) {
      silentLog('media_cache', 'download timeout', error, stack);
      await _deleteEntity(tempFile, 'delete timed-out cached media temp file');
      return null;
    } catch (error, stack) {
      silentLog('media_cache', 'download', error, stack);
      await _deleteEntity(tempFile, 'delete failed cached media temp file');
      return null;
    } finally {
      client.close(force: true);
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
      await sidecar.writeAsString(
        const JsonEncoder.withIndent('  ').convert(metadata),
        flush: true,
      );
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
    await Future.wait(<Future<void>>[
      _clearDirectoryContents(Directory(cacheDirectoryPath)),
      _clearDirectoryContents(Directory(legacyInlineMediaDirectoryPath)),
    ]);
  }

  static Future<MediaCacheStats> _measureDirectory(Directory dir) async {
    if (!await dir.exists()) return MediaCacheStats.empty;
    var totalBytes = 0;
    var fileCount = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        try {
          totalBytes += await entity.length();
          fileCount++;
        } catch (error, stack) {
          silentLog('media_cache', 'read cached file length', error, stack);
        }
      }
    } catch (error, stack) {
      silentLog('media_cache', 'list cache directory size', error, stack);
    }
    return MediaCacheStats(bytes: totalBytes, fileCount: fileCount);
  }

  static Future<void> _clearDirectoryContents(Directory dir) async {
    if (!await dir.exists()) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        await _deleteEntity(entity, 'delete cached media entity');
      }
    } catch (error, stack) {
      silentLog('media_cache', 'list cache directory clear', error, stack);
    }
  }

  static Future<void> _deleteEntity(
    FileSystemEntity entity,
    String where,
  ) async {
    try {
      if (await entity.exists()) {
        await entity.delete(recursive: true);
      }
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

  static bool _looksUsableFile(File file) {
    try {
      return file.existsSync() && file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  static void _deleteInvalidCachePair(String mediaPath) {
    try {
      final file = File(mediaPath);
      if (file.existsSync()) file.deleteSync();
    } catch (error, stack) {
      silentLog('media_cache', 'delete invalid cached media', error, stack);
    }
    try {
      final sidecar = File(_metadataPathForMediaPath(mediaPath));
      if (sidecar.existsSync()) sidecar.deleteSync();
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
