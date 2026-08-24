/// 远程 AI 媒体持久缓存。
///
/// 将聊天中的远程图片、视频和音频缓存到 `~/.openhand/cache/media`，并写入
/// JSON 元数据，确保缓存可追踪、可统计且可从设置中清理。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/net/bounded_http_request.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_response_utils.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_delete.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
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
  MediaCacheService._()
    : _validatedCachePaths = LifecycleLruCache<DateTime>(
        maxEntries: _validatedPathCacheMaxEntries,
      ),
      _cacheDirectoryPathProvider =
          OpenHandPaths.defaultMediaCacheDirectoryPath,
      _createHttpClient = ((connectionTimeout) => SystemProxyResolver.instance
          .createRawHttpClient(connectionTimeout: connectionTimeout));

  static final MediaCacheService instance = MediaCacheService._();

  static const Duration runtimeCleanupTimeout = Duration(seconds: 20);

  static const Duration _requestOpenTimeout = Duration(seconds: 20);
  static const Duration _responseHeaderTimeout = Duration(seconds: 30);
  static const Duration _responseChunkTimeout = Duration(seconds: 30);
  static const Duration _fileOperationTimeout = Duration(seconds: 30);
  static const Duration _downloadQueueTimeout = Duration(seconds: 30);
  static const Duration _commitQueueTimeout = Duration(seconds: 30);
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
  static const int _maxTotalCacheBytes = 4 * kBytesPerGiB;
  static const int _maxCachedMediaFiles = 2048;
  static const int _maxConcurrentDownloads = 4;
  static const int _maxPendingDownloads = 64;
  static const int _maxPendingCommits = 64;
  static const int _maxPendingInvalidations = 4096;
  static const int _validatedPathCacheMaxEntries = 2048;
  static const Duration _validatedPathTtl = Duration(seconds: 5);
  static const Duration _staleTempFileAge = Duration(minutes: 30);

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
  final LifecycleLruCache<DateTime> _validatedCachePaths;
  final OpenHandAsyncSemaphore _downloadSemaphore = OpenHandAsyncSemaphore(
    _maxConcurrentDownloads,
    maxWaiters: _maxPendingDownloads,
  );
  final OpenHandAsyncSemaphore _commitSemaphore = OpenHandAsyncSemaphore(
    1,
    maxWaiters: _maxPendingCommits,
  );
  final Set<HttpClient> _activeClients = <HttpClient>{};
  final Set<Future<void>> _activeImports = <Future<void>>{};
  final Set<String> _pendingInvalidations = <String>{};
  final String Function() _cacheDirectoryPathProvider;
  final HttpClient Function(Duration connectionTimeout) _createHttpClient;
  Directory? _cacheDir;
  int _generation = 0;
  int _tempFileSerial = 0;
  bool _clearing = false;
  bool _disposed = false;
  final OpenHandSingleFlight<void> _clearFlight = OpenHandSingleFlight<void>();
  Future<void>? _invalidationWorker;
  Future<void>? _prewarmFuture;
  Future<void>? _shutdownFuture;

  static String get cacheDirectoryPath =>
      OpenHandPaths.defaultMediaCacheDirectoryPath();

  static String get legacyInlineMediaDirectoryPath =>
      p.join(Directory.systemTemp.path, 'openhand_media');

  Future<void> prewarm() {
    final active = _prewarmFuture;
    if (active != null) return active;
    final prewarm = _withCommitPermit<void>(() async {
      if (_disposed || _clearing) return;
      final directory = Directory(_cacheDirectoryPathProvider());
      if (await directory.exists().timeout(_fileOperationTimeout)) {
        await _pruneCacheDirectory(directory);
      }
    });
    _prewarmFuture = prewarm;
    unawaited(
      prewarm.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_prewarmFuture, prewarm)) {
            _prewarmFuture = null;
          }
        },
      ),
    );
    return prewarm;
  }

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

  /// 返回异步缓存任务已验证的路径；同步热路径不执行文件系统操作。
  String? cachedPathForUrl(String url, {MediaCacheKind? kind}) {
    final uri = _httpUriOrNull(url);
    if (uri == null) return null;
    final normalizedUrl = uri.toString();
    final effectiveKind = kind ?? _kindFromUrl(normalizedUrl);
    final path = _cacheFilePathForUrl(
      normalizedUrl,
      _cacheDirectoryPathProvider(),
      effectiveKind,
    );
    final validatedAt = _validatedCachePaths.get(path);
    final age = validatedAt == null
        ? null
        : DateTime.now().toUtc().difference(validatedAt);
    if (age == null || age.isNegative || age > _validatedPathTtl) {
      _validatedCachePaths.remove(path);
      return null;
    }
    return path;
  }

  void invalidate(String url, {MediaCacheKind? kind}) {
    if (_disposed || _clearing) return;
    final uri = _httpUriOrNull(url);
    if (uri == null) return;
    final normalizedUrl = uri.toString();
    final effectiveKind = kind ?? _kindFromUrl(normalizedUrl);
    final path = _cacheFilePathForUrl(
      normalizedUrl,
      _cacheDirectoryPathProvider(),
      effectiveKind,
    );
    _queueInvalidation(path);
  }

  void _queueInvalidation(String path) {
    _validatedCachePaths.remove(path);
    if (_disposed || _clearing) return;
    if (_pendingInvalidations.length >= _maxPendingInvalidations &&
        !_pendingInvalidations.contains(path)) {
      _pendingInvalidations.remove(_pendingInvalidations.first);
    }
    _pendingInvalidations.add(path);
    _startInvalidationWorker();
  }

  void _startInvalidationWorker() {
    if (_invalidationWorker != null ||
        _pendingInvalidations.isEmpty ||
        _disposed ||
        _clearing) {
      return;
    }
    _invalidationWorker = _drainInvalidations();
  }

  Future<void> _drainInvalidations() async {
    var completedNormally = false;
    try {
      while (_pendingInvalidations.isNotEmpty && !_disposed && !_clearing) {
        final path = _pendingInvalidations.first;
        await _withCommitPermit<void>(() async {
          if (_disposed || _clearing || !_pendingInvalidations.remove(path)) {
            return;
          }
          await _deleteInvalidCachePair(path);
        });
      }
      completedNormally = true;
    } on _MediaCacheCancelled {
      return;
    } catch (error, stack) {
      silentLog('media_cache', '使媒体缓存失效', error, stack);
    } finally {
      _invalidationWorker = null;
      if (completedNormally &&
          _pendingInvalidations.isNotEmpty &&
          !_disposed &&
          !_clearing) {
        _startInvalidationWorker();
      }
    }
  }

  /// 确保 [url] 存在本地缓存并返回路径；失败时返回空，调用方可回退网络地址。
  Future<String?> ensureCached(
    String url, {
    MediaCacheKind? kind,
    Future<void>? cancelSignal,
  }) async {
    try {
      if (_disposed || _clearing) return null;
      final uri = _httpUriOrNull(url);
      if (uri == null) return null;
      final normalizedUrl = uri.toString();
      final effectiveKind = kind ?? _kindFromUrl(normalizedUrl);
      final generation = _generation;
      final cached = await _validatedCachedPath(
        normalizedUrl,
        kind: effectiveKind,
        generation: generation,
      );
      if (_disposed || _clearing || generation != _generation) return null;
      if (cached != null) return cached;
      final cacheKey = _inflightKey(normalizedUrl, effectiveKind);
      final active = _inflight[cacheKey];
      if (active != null) {
        final result = await awaitWithCancelSignal<String?>(
          active,
          cancelSignal: cancelSignal,
        );
        if (_disposed || _clearing || generation != _generation) return null;
        return result;
      }
      if (_inflight.length + _activeImports.length >=
          _maxConcurrentDownloads + _maxPendingDownloads) {
        return null;
      }
      final future = _runDownloadOperation(() {
        if (_disposed || _clearing || generation != _generation) {
          return Future<String?>.value();
        }
        return _downloadAndCache(
          uri,
          kind: effectiveKind,
          generation: generation,
        );
      });
      _inflight[cacheKey] = future;
      unawaited(
        future.then<void>(
          (_) {
            if (identical(_inflight[cacheKey], future)) {
              _inflight.remove(cacheKey);
            }
          },
          onError: (Object _, StackTrace _) {
            if (identical(_inflight[cacheKey], future)) {
              _inflight.remove(cacheKey);
            }
          },
        ),
      );
      final result = await awaitWithCancelSignal<String?>(
        future,
        cancelSignal: cancelSignal,
      );
      if (_disposed || _clearing || generation != _generation) return null;
      return result;
    } on _MediaCacheCancelled {
      return null;
    } catch (error, stack) {
      silentLog('media_cache', '确保媒体缓存可用', error, stack);
      return null;
    }
  }

  /// 启动尽力执行的后台缓存任务，界面调用方无需等待。
  void cacheInBackground(String url, {MediaCacheKind? kind}) {
    final uri = _httpUriOrNull(url);
    if (uri == null) return;
    unawaited(ensureCached(uri.toString(), kind: kind));
  }

  Future<String?> _runDownloadOperation(
    Future<String?> Function() operation,
  ) async {
    late final bool acquired;
    try {
      acquired = await _downloadSemaphore.acquireWithin(_downloadQueueTimeout);
    } on StateError {
      return null;
    }
    if (!acquired) return null;
    try {
      if (_disposed || _clearing) return null;
      return await operation();
    } finally {
      _downloadSemaphore.release();
    }
  }

  Future<T> _withCommitPermit<T>(Future<T> Function() operation) async {
    late final bool acquired;
    try {
      acquired = await _commitSemaphore.acquireWithin(_commitQueueTimeout);
    } on StateError {
      if (_disposed || _clearing) throw const _MediaCacheCancelled();
      throw StateError('媒体缓存提交队列已满。');
    }
    if (!acquired) {
      if (_disposed || _clearing) throw const _MediaCacheCancelled();
      throw TimeoutException('媒体缓存提交排队超时。', _commitQueueTimeout);
    }
    try {
      return await operation();
    } finally {
      _commitSemaphore.release();
    }
  }

  /// 将已下载文件导入确定性缓存，避免“另存为”后再次下载相同媒体用于预热。
  Future<String?> importFile(
    String url,
    String sourcePath, {
    MediaCacheKind? kind,
    String? mimeType,
  }) async {
    if (_disposed || _clearing) return null;
    if (_inflight.length + _activeImports.length >=
        _maxConcurrentDownloads + _maxPendingDownloads) {
      return null;
    }
    final completer = Completer<void>();
    final operation = completer.future;
    final generation = _generation;
    _activeImports.add(operation);
    try {
      return await _runDownloadOperation(() {
        if (_disposed || _clearing || generation != _generation) {
          return Future<String?>.value();
        }
        return _importFile(
          url,
          sourcePath,
          kind: kind,
          mimeType: mimeType,
          generation: generation,
        );
      });
    } on _MediaCacheCancelled {
      return null;
    } catch (error, stack) {
      silentLog('media_cache', '导入本地媒体文件', error, stack);
      return null;
    } finally {
      completer.complete();
      _activeImports.remove(operation);
    }
  }

  Future<String?> _importFile(
    String url,
    String sourcePath, {
    required MediaCacheKind? kind,
    required String? mimeType,
    required int generation,
  }) async {
    final uri = _httpUriOrNull(url);
    final normalizedSourcePath = nullIfBlank(sourcePath);
    if (uri == null || normalizedSourcePath == null) return null;
    final sourceFile = File(normalizedSourcePath);
    final sourceStat = await _usableFileStat(sourceFile);
    if (sourceStat == null) return null;
    final normalizedUrl = uri.toString();
    final cacheKind = kind ?? _kindFromUrl(normalizedUrl);
    final cached = await _validatedCachedPath(
      normalizedUrl,
      kind: cacheKind,
      generation: generation,
    );
    if (_disposed || _clearing || generation != _generation) return null;
    if (cached != null) return cached;
    final maxBytes = _maxBytesForKind(cacheKind);
    final bytes = sourceStat.size;
    if (bytes <= 0 || bytes > maxBytes) return null;

    final dir = await _ensureCacheDir();
    if (_disposed || _clearing || generation != _generation) return null;
    final destPath = _cacheFilePathForUrl(normalizedUrl, dir.path, cacheKind);
    final tempFile = _uniqueTempFile(destPath, generation);
    try {
      final written = await _writeMediaStream(
        sourceFile.openRead(0, bytes).timeout(_fileOperationTimeout),
        tempFile: tempFile,
        maxBytes: maxBytes,
        totalTimeout: _deadlineForKind(cacheKind),
        generation: generation,
      );
      final finalSourceStat = await _usableFileStat(sourceFile);
      if (written != bytes ||
          finalSourceStat == null ||
          !_sameFileVersion(sourceStat, finalSourceStat)) {
        throw FileSystemException('导入源文件在复制期间发生变化。', normalizedSourcePath);
      }
      return await _commitTempFile(
        tempFile: tempFile,
        destPath: destPath,
        url: normalizedUrl,
        kind: cacheKind,
        mimeType: mimeType,
        generation: generation,
      );
    } on _MediaCacheCancelled {
      await _deleteEntity(tempFile, '删除已取消导入的媒体临时文件');
      return null;
    } catch (error, stack) {
      silentLog('media_cache', '导入本地媒体文件', error, stack);
      await _deleteEntity(tempFile, '删除导入失败的媒体临时文件');
      return null;
    }
  }

  Future<String?> _downloadAndCache(
    Uri uri, {
    required MediaCacheKind? kind,
    required int generation,
  }) async {
    final normalizedUrl = uri.toString();
    final cacheKind = kind ?? _kindFromUrl(normalizedUrl);
    final deadline = MonotonicDeadline(
      _deadlineForKind(cacheKind),
      timeoutMessage: '媒体缓存下载超过总时限。',
    );
    File? tempFile;
    HttpClient? client;
    try {
      final dir = await _ensureCacheDir();
      if (_disposed || _clearing || generation != _generation) return null;
      final destPath = _cacheFilePathForUrl(normalizedUrl, dir.path, cacheKind);
      tempFile = _uniqueTempFile(destPath, generation);
      final httpClient = _createHttpClient(_requestOpenTimeout);
      client = httpClient;
      _activeClients.add(httpClient);
      final request = await openHttpClientRequestBounded(
        () => httpClient.getUrl(uri),
        timeout: deadline.limit(_requestOpenTimeout),
        timeoutMessage: '媒体缓存请求打开超时。',
      );
      final response = await closeHttpClientRequestBounded(
        request,
        timeout: deadline.limit(_responseHeaderTimeout),
        timeoutMessage: '媒体缓存响应头获取超时。',
      );
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

      final remainingBodyTime = deadline.remaining();
      final boundedResponse = limitByteStream(
        response,
        maxBytes: maxBytes,
        idleTimeout: deadline.limit(_responseChunkTimeout),
        totalTimeout: remainingBodyTime,
      );
      final written = await _writeMediaStream(
        boundedResponse,
        tempFile: tempFile,
        maxBytes: maxBytes,
        totalTimeout: deadline.remaining(),
        generation: generation,
      );
      if (written <= 0) {
        await _deleteEntity(tempFile, '删除空媒体缓存临时文件');
        return null;
      }

      return await _commitTempFile(
        tempFile: tempFile,
        destPath: destPath,
        url: normalizedUrl,
        kind: cacheKind,
        mimeType: contentType?.mimeType,
        generation: generation,
      );
    } on _MediaCacheCancelled {
      if (tempFile != null) {
        await _deleteEntity(tempFile, '删除已取消的媒体缓存临时文件');
      }
      return null;
    } on TimeoutException catch (error, stack) {
      silentLog('media_cache', '媒体缓存下载超时', error, stack);
      if (tempFile != null) {
        await _deleteEntity(tempFile, '删除下载超时的媒体缓存临时文件');
      }
      return null;
    } catch (error, stack) {
      silentLog('media_cache', '下载媒体缓存', error, stack);
      if (tempFile != null) {
        await _deleteEntity(tempFile, '删除下载失败的媒体缓存临时文件');
      }
      return null;
    } finally {
      deadline.stop();
      if (client != null) _activeClients.remove(client);
      try {
        client?.close(force: true);
      } catch (error, stack) {
        silentLog('media_cache', '关闭媒体缓存下载客户端', error, stack);
      }
    }
  }

  File _uniqueTempFile(String destPath, int generation) {
    final serial = _tempFileSerial++;
    return File('$destPath.part.$generation.$serial');
  }

  Future<int> _writeMediaStream(
    Stream<List<int>> stream, {
    required File tempFile,
    required int maxBytes,
    required Duration totalTimeout,
    required int generation,
  }) async {
    final deadline = MonotonicDeadline(
      totalTimeout,
      timeoutMessage: '媒体缓存写入超过总时限。',
    );
    BoundedRandomAccessFileLease? output;
    var deleteOnRelease = false;
    var written = 0;
    try {
      await tempFile.parent
          .create(recursive: true)
          .timeout(deadline.limit(_fileOperationTimeout));
      final openedOutput = await openBoundedRandomAccessFileLease(
        tempFile,
        mode: FileMode.write,
        timeout: deadline.limit(_fileOperationTimeout),
        deleteIfOpenCompletesLate: true,
        release: (file) async {
          await file.close();
          if (deleteOnRelease) {
            await _deleteEntity(tempFile, '删除未完成的媒体缓存临时文件');
          }
        },
      );
      output = openedOutput;
      await for (final chunk in stream) {
        if (_disposed || _clearing || generation != _generation) {
          throw const _MediaCacheCancelled();
        }
        written += chunk.length;
        if (written > maxBytes) {
          throw FileSystemException('媒体缓存写入超过大小限制。', tempFile.path);
        }
        await openedOutput.run<void>(
          (file) => file.writeFrom(chunk),
          timeout: deadline.limit(_fileOperationTimeout),
        );
      }
      await openedOutput.run<void>(
        (file) => file.flush(),
        timeout: deadline.limit(_fileOperationTimeout),
      );
      await openedOutput.close(timeout: deadline.limit(_cleanupTimeout));
      output = null;
      return written;
    } finally {
      deadline.stop();
      deleteOnRelease = output != null;
      await output?.cleanup();
    }
  }

  Future<String?> _commitTempFile({
    required File tempFile,
    required String destPath,
    required String url,
    required MediaCacheKind? kind,
    required String? mimeType,
    required int generation,
  }) {
    return _withCommitPermit<String?>(() async {
      if (_disposed || _clearing || generation != _generation) {
        await _deleteEntity(tempFile, '删除失效的媒体缓存临时文件');
        return null;
      }
      final destFile = File(destPath);
      if (await _looksUsableFile(destFile)) {
        await _deleteEntity(tempFile, '删除重复的媒体缓存临时文件');
      } else {
        await _deleteInvalidCachePair(destPath);
        final publishing = tempFile.rename(destPath);
        try {
          await publishing.timeout(_fileOperationTimeout);
        } on TimeoutException {
          _queueInvalidation(destPath);
          unawaited(_cleanupLateCachePublish(publishing, tempFile, destPath));
          rethrow;
        }
      }
      if (!await _looksUsableFile(destFile)) return null;
      final bytes = await destFile.length().timeout(_fileOperationTimeout);
      await _writeMetadata(
        mediaPath: destPath,
        url: url,
        kind: kind,
        mimeType: mimeType,
        bytes: bytes,
      );
      await _pruneCacheDirectory(destFile.parent);
      if (!await _looksUsableFile(destFile)) return null;
      if (_disposed ||
          _clearing ||
          generation != _generation ||
          _pendingInvalidations.contains(destPath)) {
        _validatedCachePaths.remove(destPath);
        return null;
      }
      _validatedCachePaths.put(destPath, DateTime.now().toUtc());
      return destPath;
    });
  }

  static Future<void> _cleanupLateCachePublish(
    Future<File> publishing,
    File tempFile,
    String destPath,
  ) async {
    var published = false;
    try {
      await publishing;
      published = true;
    } catch (error, stack) {
      silentLog('media_cache', '等待延迟发布媒体缓存', error, stack);
    }
    await _deleteEntity(tempFile, '删除延迟发布的媒体缓存临时文件');
    if (published) await _deleteInvalidCachePair(destPath);
  }

  Future<void> _pruneCacheDirectory(Directory directory) async {
    if (!await directory.exists().timeout(_cleanupTimeout)) return;
    final entries = <_MediaCacheEntry>[];
    final sidecars = <File>[];
    var totalBytes = 0;
    var scannedEntries = 0;
    final deadline = MonotonicDeadline(
      _cacheScanTimeout,
      timeoutMessage: '媒体缓存清理超过总时限。',
    );
    try {
      await for (final entity
          in directory.list(followLinks: false).timeout(_cleanupTimeout)) {
        scannedEntries += 1;
        if (scannedEntries > _maxCacheScanEntries) {
          throw StateError('媒体缓存扫描超过条目上限。');
        }
        if (deadline.isExpired) throw deadline.timeoutException();
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.endsWith('.json')) {
          sidecars.add(entity);
          continue;
        }
        if (name.endsWith('.part') || name.contains('.part.')) {
          final stat = await _statFileIfPresent(entity);
          if (stat == null) continue;
          if (DateTime.now().difference(stat.modified) > _staleTempFileAge) {
            await _deleteEntity(entity, '删除过期媒体缓存临时文件');
          }
          continue;
        }
        final stat = await _statFileIfPresent(entity);
        if (stat == null || stat.type != FileSystemEntityType.file) continue;
        if (stat.size <= 0) {
          await _deleteInvalidCachePair(entity.path);
          continue;
        }
        entries.add(
          _MediaCacheEntry(
            path: entity.path,
            bytes: stat.size,
            modified: stat.modified,
          ),
        );
        totalBytes += stat.size;
      }
      final expectedSidecars = entries
          .map((entry) => _metadataPathForMediaPath(entry.path))
          .toSet();
      for (final sidecar in sidecars) {
        if (deadline.isExpired) throw deadline.timeoutException();
        if (!expectedSidecars.contains(sidecar.path)) {
          await _deleteEntity(sidecar, '删除孤立媒体缓存元数据');
        }
      }
      if (entries.length <= _maxCachedMediaFiles &&
          totalBytes <= _maxTotalCacheBytes) {
        return;
      }
      entries.sort((left, right) => left.modified.compareTo(right.modified));
      var remainingFiles = entries.length;
      for (final entry in entries) {
        if (deadline.isExpired) throw deadline.timeoutException();
        if (remainingFiles <= _maxCachedMediaFiles &&
            totalBytes <= _maxTotalCacheBytes) {
          break;
        }
        await _deleteInvalidCachePair(entry.path);
        if (!await File(entry.path).exists().timeout(_cleanupTimeout)) {
          totalBytes -= entry.bytes;
          remainingFiles--;
          _validatedCachePaths.remove(entry.path);
        }
      }
    } finally {
      deadline.stop();
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
      await writeFileAtomically(sidecar, prettyPrintJson(metadata));
    } catch (error, stack) {
      silentLog('media_cache', '写入媒体缓存元数据', error, stack);
    }
  }

  static Future<MediaCacheStats> measureCache() async {
    final persistent = await _measureDirectory(Directory(cacheDirectoryPath));
    final legacy = await _measureDirectory(
      Directory(legacyInlineMediaDirectoryPath),
    );
    return persistent + legacy;
  }

  static Future<void> clearCache() async {
    await instance._clearCacheResources();
  }

  Future<void> shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    _disposed = true;
    return _shutdownFuture = _performShutdown();
  }

  Future<void> _performShutdown() async {
    _clearing = true;
    _generation++;
    _validatedCachePaths.clear();
    _pendingInvalidations.clear();
    final deadline = MonotonicDeadline(
      runtimeCleanupTimeout,
      timeoutMessage: '媒体缓存关闭超过总时限。',
    );
    try {
      await _cancelActiveOperations(
        timeout: deadline.limit(_cacheScanTimeout),
        waitForCacheClear: true,
      );
      final acquired = await _commitSemaphore.acquireWithin(
        deadline.remaining(),
      );
      if (!acquired) throw deadline.timeoutException();
      _commitSemaphore.release();
    } finally {
      deadline.stop();
      _clearing = false;
    }
  }

  Future<void> _clearCacheResources() {
    return _clearFlight.run(_performCacheClear);
  }

  Future<void> _performCacheClear() async {
    _clearing = true;
    _generation++;
    _validatedCachePaths.clear();
    _pendingInvalidations.clear();
    _cacheDir = null;
    try {
      await _cancelActiveOperations();
      final acquired = await _commitSemaphore.acquireWithin(
        _fileOperationTimeout,
      );
      if (!acquired) {
        throw TimeoutException('等待媒体缓存写入结束超时。', _fileOperationTimeout);
      }
      try {
        await Future.wait(<Future<void>>[
          _clearDirectoryContents(Directory(cacheDirectoryPath)),
          _clearDirectoryContents(Directory(legacyInlineMediaDirectoryPath)),
        ]);
        _cacheDir = null;
        _validatedCachePaths.clear();
        _pendingInvalidations.clear();
      } finally {
        _commitSemaphore.release();
      }
    } finally {
      _clearing = false;
    }
  }

  Future<void> _cancelActiveOperations({
    Duration timeout = _cleanupTimeout,
    bool waitForCacheClear = false,
  }) async {
    _downloadSemaphore.cancelWaiters();
    _commitSemaphore.cancelWaiters();
    for (final client in _activeClients.toList(growable: false)) {
      try {
        client.close(force: true);
      } catch (error, stack) {
        silentLog('media_cache', '取消活动媒体下载', error, stack);
      }
    }
    final pending = <Future<void>>[
      for (final operation in _inflight.values)
        operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      for (final operation in _activeImports)
        operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      if (_invalidationWorker case final worker?)
        worker.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      if (_prewarmFuture case final prewarm?)
        prewarm.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      if (waitForCacheClear && _clearFlight.isRunning)
        _clearFlight.idle.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
    ];
    if (pending.isNotEmpty) {
      await Future.wait<void>(
        pending,
      ).timeout(timeout, onTimeout: () => <void>[]);
    }
    _inflight.clear();
  }

  static Future<MediaCacheStats> _measureDirectory(Directory dir) async {
    if (!await dir.exists().timeout(_cleanupTimeout)) {
      return MediaCacheStats.empty;
    }
    final usage = await measureDirectoryBounded(
      dir,
      maxEntries: _maxCacheScanEntries,
      totalTimeout: _cacheScanTimeout,
      operationTimeout: _cleanupTimeout,
    );
    return MediaCacheStats(bytes: usage.totalBytes, fileCount: usage.fileCount);
  }

  static Future<void> _clearDirectoryContents(Directory dir) async {
    await deletePathBounded(p.absolute(dir.path), policy: _cacheDeletePolicy);
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
    required MediaCacheKind? kind,
    required int generation,
  }) {
    final path = _cacheFilePathForUrl(url, _cacheDirectoryPathProvider(), kind);
    return _withCommitPermit<String?>(() async {
      if (_disposed || _clearing || generation != _generation) return null;
      if (_pendingInvalidations.remove(path)) {
        await _deleteInvalidCachePair(path);
      }
      if (_disposed || _clearing || generation != _generation) return null;
      final file = File(path);
      if (await _looksUsableFile(file)) {
        final now = DateTime.now().toUtc();
        try {
          await file.setLastModified(now).timeout(_fileOperationTimeout);
        } on FileSystemException {
          // 缓存有效性不依赖访问时间刷新能力。
        }
        if (_disposed ||
            _clearing ||
            generation != _generation ||
            _pendingInvalidations.contains(path)) {
          return null;
        }
        _validatedCachePaths.put(path, now);
        return path;
      }
      _validatedCachePaths.remove(path);
      await _deleteInvalidCachePair(path);
      return null;
    });
  }

  static Future<bool> _looksUsableFile(File file) async {
    return await _usableFileStat(file) != null;
  }

  static Future<FileStat?> _usableFileStat(File file) async {
    try {
      final type = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      ).timeout(_fileOperationTimeout);
      if (type != FileSystemEntityType.file) return null;
      final stat = await file.stat().timeout(_fileOperationTimeout);
      return stat.type == FileSystemEntityType.file && stat.size > 0
          ? stat
          : null;
    } catch (_) {
      return null;
    }
  }

  static bool _sameFileVersion(FileStat before, FileStat after) {
    return before.type == after.type &&
        before.size == after.size &&
        before.modified == after.modified &&
        before.changed == after.changed;
  }

  static Future<FileStat?> _statFileIfPresent(File file) async {
    try {
      return await file.stat().timeout(_cleanupTimeout);
    } on FileSystemException {
      if (!await file.exists().timeout(_cleanupTimeout)) return null;
      rethrow;
    }
  }

  static Future<void> _deleteInvalidCachePair(String mediaPath) async {
    try {
      final file = File(mediaPath);
      if (await file.exists().timeout(_cleanupTimeout)) {
        await file.delete().timeout(_cleanupTimeout);
      }
    } catch (error, stack) {
      silentLog('media_cache', '删除无效媒体缓存', error, stack);
    }
    try {
      final sidecar = File(_metadataPathForMediaPath(mediaPath));
      if (await sidecar.exists().timeout(_cleanupTimeout)) {
        await sidecar.delete().timeout(_cleanupTimeout);
      }
    } catch (error, stack) {
      silentLog('media_cache', '删除无效媒体缓存元数据', error, stack);
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
    return contentType.mimeType == kApplicationOctetStreamMimeType;
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
      silentLog('media_cache', '解析媒体地址扩展名', error, stack);
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

class _MediaCacheEntry {
  const _MediaCacheEntry({
    required this.path,
    required this.bytes,
    required this.modified,
  });

  final String path;
  final int bytes;
  final DateTime modified;
}

class _MediaCacheCancelled implements Exception {
  const _MediaCacheCancelled();
}
