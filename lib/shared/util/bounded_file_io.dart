import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'argument_guards.dart';
import 'async_concurrency.dart';
import 'bounded_delete.dart';
import 'bounded_directory_io.dart';
import 'byte_size_format.dart';
import 'path_safety.dart';
import 'text_clip.dart';

const int _boundedFileReadChunkBytes = 64 * kBytesPerKiB;
const Duration _boundedFileCleanupTimeout = Duration(seconds: 2);
const BoundedDeletePolicy _temporaryDirectoryCleanupPolicy =
    BoundedDeletePolicy(
      maxEntries: 16,
      maxDepth: 2,
      operationTimeout: _boundedFileCleanupTimeout,
      totalTimeout: Duration(seconds: 6),
    );
const Duration defaultBoundedFileReadIdleTimeout = Duration(seconds: 3);
const Duration defaultBoundedFileReadTotalTimeout = Duration(seconds: 10);
const int _posixFileTypeMask = 0xF000;
const int _posixRegularFileType = 0x8000;
final Set<String> _activeTemporaryFilePaths = <String>{};

enum BoundedFileReadFailure { tooLarge, changedDuringRead }

String _temporaryFilePathKey(String path) => p.normalize(p.absolute(path));

/// 登记正在写入或使用的临时文件，避免同进程清理任务误删。
void registerActiveTemporaryFile(File file) {
  _activeTemporaryFilePaths.add(_temporaryFilePathKey(file.path));
}

/// 临时文件不再使用后解除登记；实际删除由调用方按自身生命周期执行。
void unregisterActiveTemporaryFile(File file) {
  _activeTemporaryFilePaths.remove(_temporaryFilePathKey(file.path));
}

/// 在单个明确目录内清理指定前后缀的临时文件。
///
/// 扫描数量、总耗时和单次文件操作均受限；当前进程正在使用的文件不会被删除。
Future<void> pruneTemporaryFilesBounded(
  Directory directory, {
  required String fileNamePrefix,
  String? fileNameSuffix,
  required int maxRetainedFiles,
  required Duration maxAge,
  required Duration timeout,
  int scanLimit = 256,
  OpenHandAsyncCleanupErrorHandler? onError,
}) async {
  if (fileNamePrefix.isEmpty) {
    throw ArgumentError.value(fileNamePrefix, 'fileNamePrefix', '不能为空。');
  }
  if (fileNameSuffix != null && fileNameSuffix.isEmpty) {
    throw ArgumentError.value(fileNameSuffix, 'fileNameSuffix', '不能为空。');
  }
  requireNonNegativeInt(maxRetainedFiles, 'maxRetainedFiles');
  requirePositiveDuration(maxAge, 'maxAge');
  requirePositiveDuration(timeout, 'timeout');
  requirePositiveInt(scanLimit, 'scanLimit');

  final deadline = MonotonicDeadline(timeout, timeoutMessage: '清理临时文件超过总时限。');
  Object? firstError;
  StackTrace? firstStack;
  void captureError(Object error, StackTrace stack) {
    firstError ??= error;
    firstStack ??= stack;
  }

  try {
    final listing = await listDirectoryBounded(
      directory,
      maxEntries: scanLimit,
      idleTimeout: deadline.limit(defaultBoundedDirectoryIdleTimeout),
      totalTimeout: deadline.remaining(),
    );
    final candidates = <({File file, DateTime modified})>[];
    for (final entry in listing.entries) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      if (!name.startsWith(fileNamePrefix) ||
          (fileNameSuffix != null && !name.endsWith(fileNameSuffix))) {
        continue;
      }
      if (_activeTemporaryFilePaths.contains(
        _temporaryFilePathKey(entry.path),
      )) {
        continue;
      }
      try {
        final stat = await entry.stat().timeout(
          deadline.limit(defaultBoundedFileReadIdleTimeout),
        );
        if (stat.type == FileSystemEntityType.file) {
          candidates.add((file: entry, modified: stat.modified));
        }
      } catch (error, stack) {
        captureError(error, stack);
      }
    }
    candidates.sort((left, right) => right.modified.compareTo(left.modified));
    final cutoff = DateTime.now().subtract(maxAge);
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      if (index < maxRetainedFiles && !candidate.modified.isBefore(cutoff)) {
        continue;
      }
      if (_activeTemporaryFilePaths.contains(
        _temporaryFilePathKey(candidate.file.path),
      )) {
        continue;
      }
      try {
        await candidate.file.delete().timeout(
          deadline.limit(_boundedFileCleanupTimeout),
        );
      } catch (error, stack) {
        captureError(error, stack);
      }
    }
  } catch (error, stack) {
    captureError(error, stack);
  } finally {
    deadline.stop();
    final error = firstError;
    final stack = firstStack;
    if (error != null && stack != null) {
      _reportSecondaryFileError(onError, error, stack);
    }
  }
}

/// 在限定时间内读取普通文件大小；文件不存在、类型不符或探测超时返回 null。
Future<int?> probeFileSizeBounded(
  File file, {
  Duration timeout = defaultBoundedFileReadIdleTimeout,
}) async {
  requirePositiveDuration(timeout, 'timeout');
  try {
    final stat = await file.stat().timeout(timeout);
    return stat.type == FileSystemEntityType.file ? stat.size : null;
  } on FileSystemException {
    return null;
  } on TimeoutException {
    return null;
  }
}

/// 在指定父目录内创建临时目录，并在创建超时后接管迟到结果的清理。
Future<Directory> createTemporaryDirectoryBounded({
  Directory? parent,
  required String prefix,
  required Duration timeout,
  BoundedDeletePolicy cleanupPolicy = _temporaryDirectoryCleanupPolicy,
  String? allowedRoot,
  OpenHandAsyncCleanupErrorHandler? onSecondaryError,
}) async {
  requirePositiveDuration(timeout, 'timeout');
  final root = parent ?? Directory.systemTemp;
  final safePrefix = sanitizePortableFileNamePart(
    prefix,
    fallback: 'openhand-temp-',
    maxCharacters: 64,
    collapseReplacement: true,
  );
  final create = root.createTemp(safePrefix);
  var waitTimedOut = false;
  try {
    return await create.timeout(
      timeout,
      onTimeout: () {
        waitTimedOut = true;
        throw TimeoutException('临时目录创建超过时限。', timeout);
      },
    );
  } on TimeoutException {
    if (!waitTimedOut) rethrow;
    unawaited(
      create.then<void>(
        (directory) => deleteTemporaryDirectoryBounded(
          directory,
          policy: cleanupPolicy,
          allowedRoot: p.absolute(allowedRoot ?? root.path),
          onError: onSecondaryError,
        ),
        onError: (Object error, StackTrace stack) =>
            _reportSecondaryFileError(onSecondaryError, error, stack),
      ),
    );
    rethrow;
  }
}

/// 删除受管临时目录，不跟随符号链接，并限制条目、深度和总耗时。
///
/// 清理失败返回 `false`，同时可通过 [onError] 记录错误；默认只允许删除系统
/// 临时目录内的目标。
Future<bool> deleteTemporaryDirectoryBounded(
  Directory? directory, {
  BoundedDeletePolicy policy = _temporaryDirectoryCleanupPolicy,
  String? allowedRoot,
  OpenHandAsyncCleanupErrorHandler? onError,
}) async {
  if (directory == null) return true;
  try {
    await deletePathBounded(
      p.absolute(directory.path),
      policy: policy,
      allowedRoot: p.absolute(allowedRoot ?? Directory.systemTemp.path),
    );
    return true;
  } catch (error, stack) {
    _reportSecondaryFileError(onError, error, stack);
    return false;
  }
}

/// 在系统临时目录中新建私有目录并写入二进制文件。
///
/// 创建和写入共享同一总时限；失败时删除整个临时目录，创建操作延迟完成时也会
/// 在完成后补做清理，避免空目录和半文件残留。
Future<File> writeNewTemporaryFileBytesBounded({
  required String directoryPrefix,
  required String fileName,
  required List<int> bytes,
  required Duration timeout,
  bool flush = true,
  OpenHandAsyncCleanupErrorHandler? onSecondaryError,
}) {
  return _writeNewTemporaryFileBounded(
    directoryPrefix: directoryPrefix,
    fileName: fileName,
    timeout: timeout,
    write: (file) async {
      await file.writeAsBytes(bytes, flush: flush);
    },
    onSecondaryError: onSecondaryError,
  );
}

/// 文本版本的 [writeNewTemporaryFileBytesBounded]。
Future<File> writeNewTemporaryFileTextBounded({
  required String directoryPrefix,
  required String fileName,
  required String text,
  required Duration timeout,
  Encoding encoding = utf8,
  bool flush = true,
  OpenHandAsyncCleanupErrorHandler? onSecondaryError,
}) {
  return _writeNewTemporaryFileBounded(
    directoryPrefix: directoryPrefix,
    fileName: fileName,
    timeout: timeout,
    write: (file) async {
      await file.writeAsString(text, encoding: encoding, flush: flush);
    },
    onSecondaryError: onSecondaryError,
  );
}

Future<File> _writeNewTemporaryFileBounded({
  required String directoryPrefix,
  required String fileName,
  required Duration timeout,
  required Future<void> Function(File file) write,
  required OpenHandAsyncCleanupErrorHandler? onSecondaryError,
}) async {
  requirePositiveDuration(timeout, 'timeout');
  final name = sanitizePortableFileNamePart(
    fileName,
    fallback: 'temporary-file',
    allowWhitespace: true,
    collapseReplacement: true,
  );
  final deadline = MonotonicDeadline(timeout, timeoutMessage: '临时文件写入超过总时限。');
  Directory? directory;
  try {
    directory = await createTemporaryDirectoryBounded(
      prefix: directoryPrefix,
      timeout: deadline.remaining(),
      onSecondaryError: onSecondaryError,
    );
    final file = File(p.join(directory.path, name));
    final writeTimeout = deadline.remaining();
    final writeFuture = Future<void>.sync(() => write(file));
    try {
      await writeFuture.timeout(writeTimeout);
    } on TimeoutException {
      final created = directory;
      directory = null;
      unawaited(
        writeFuture
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) =>
                  _reportSecondaryFileError(onSecondaryError, error, stack),
            )
            .whenComplete(
              () => deleteTemporaryDirectoryBounded(
                created,
                allowedRoot: p.absolute(Directory.systemTemp.path),
                onError: onSecondaryError,
              ),
            ),
      );
      rethrow;
    }
    return file;
  } catch (_) {
    final created = directory;
    if (created != null) {
      await deleteTemporaryDirectoryBounded(
        created,
        allowedRoot: p.absolute(Directory.systemTemp.path),
        onError: onSecondaryError,
      );
    }
    rethrow;
  } finally {
    deadline.stop();
  }
}

/// 在明确时限内写入临时二进制文件；失败或超时后自动删除残留文件。
///
/// Dart 文件写入无法主动取消。超时后若底层写入迟到完成，本方法会在其结束后
/// 再删除文件，避免未登记的临时文件长期残留。
Future<void> writeTemporaryFileBytesBounded(
  File file,
  List<int> bytes, {
  required Duration timeout,
  bool flush = true,
  OpenHandAsyncCleanupErrorHandler? onSecondaryError,
}) {
  return _writeTemporaryFileBounded(
    file,
    () async {
      await file.writeAsBytes(bytes, flush: flush);
    },
    timeout: timeout,
    onSecondaryError: onSecondaryError,
  );
}

/// 在明确时限内写入临时文本文件；失败清理语义与
/// [writeTemporaryFileBytesBounded] 一致。
Future<void> writeTemporaryFileTextBounded(
  File file,
  String text, {
  required Duration timeout,
  Encoding encoding = utf8,
  bool flush = true,
  OpenHandAsyncCleanupErrorHandler? onSecondaryError,
}) {
  return _writeTemporaryFileBounded(
    file,
    () async {
      await file.writeAsString(text, encoding: encoding, flush: flush);
    },
    timeout: timeout,
    onSecondaryError: onSecondaryError,
  );
}

Future<void> _writeTemporaryFileBounded(
  File file,
  Future<void> Function() write, {
  required Duration timeout,
  required OpenHandAsyncCleanupErrorHandler? onSecondaryError,
}) async {
  requirePositiveDuration(timeout, 'timeout');
  final writeFuture = Future<void>.sync(write);
  try {
    await writeFuture.timeout(timeout);
  } on TimeoutException {
    unawaited(
      writeFuture.then<void>(
        (_) => _deleteTemporaryFileAfterWriteFailure(
          file,
          onSecondaryError: onSecondaryError,
        ),
        onError: (Object error, StackTrace stack) async {
          _reportSecondaryFileError(onSecondaryError, error, stack);
          await _deleteTemporaryFileAfterWriteFailure(
            file,
            onSecondaryError: onSecondaryError,
          );
        },
      ),
    );
    rethrow;
  } catch (_) {
    await _deleteTemporaryFileAfterWriteFailure(
      file,
      onSecondaryError: onSecondaryError,
    );
    rethrow;
  }
}

Future<void> _deleteTemporaryFileAfterWriteFailure(
  File file, {
  required OpenHandAsyncCleanupErrorHandler? onSecondaryError,
}) async {
  try {
    if (await file.exists().timeout(_boundedFileCleanupTimeout)) {
      await file.delete().timeout(_boundedFileCleanupTimeout);
    }
  } catch (error, stack) {
    _reportSecondaryFileError(onSecondaryError, error, stack);
  }
}

void _reportSecondaryFileError(
  OpenHandAsyncCleanupErrorHandler? onSecondaryError,
  Object error,
  StackTrace stack,
) {
  try {
    onSecondaryError?.call(error, stack);
  } catch (_) {
    // 次要错误处理器不能覆盖原始写入结果。
  }
}

abstract interface class BoundedFileHandleOwner {
  Future<RandomAccessFile> acquireFile(
    Future<RandomAccessFile> acquisition, {
    required Duration timeout,
  });

  Future<void> releaseFile(RandomAccessFile file);
}

/// 串行执行同一 [RandomAccessFile] 上的限时异步操作；操作超时但尚未结束时延后
/// 释放。Dart 不允许同一句柄在前一异步操作结束前执行第二个操作（包括关闭），
/// 因此不能在 [Future.timeout] 后立即清理，否则可能永久泄漏句柄。
final class BoundedRandomAccessFileLease {
  BoundedRandomAccessFileLease(
    this.file, {
    this._release,
    Duration cleanupTimeout = _boundedFileCleanupTimeout,
  }) : _cleanupTimeout = cleanupTimeout {
    requirePositiveDuration(cleanupTimeout, 'cleanupTimeout');
  }

  final RandomAccessFile file;
  final Future<void> Function(RandomAccessFile file)? _release;
  final Duration _cleanupTimeout;
  Future<void>? _pendingOperation;
  Future<void>? _releaseFuture;
  bool _lateReleaseScheduled = false;
  bool _cleanupRequested = false;

  Future<T> run<T>(
    Future<T> Function(RandomAccessFile file) operation, {
    required Duration timeout,
  }) async {
    requirePositiveDuration(timeout, 'timeout');
    if (_cleanupRequested ||
        _pendingOperation != null ||
        _releaseFuture != null) {
      throw StateError('随机访问文件租约当前不可用。');
    }
    final settledCompleter = Completer<void>();
    final settled = settledCompleter.future;
    _pendingOperation = settled;
    final operationFuture = Future<T>.sync(() => operation(file));
    unawaited(
      operationFuture.then<void>(
        (_) => settledCompleter.complete(),
        onError: (Object _, StackTrace _) => settledCompleter.complete(),
      ),
    );
    var deadlineExpired = false;
    try {
      return await operationFuture.timeout(
        timeout,
        onTimeout: () {
          deadlineExpired = true;
          throw TimeoutException('随机访问文件操作超时。', timeout);
        },
      );
    } finally {
      if (!deadlineExpired && identical(_pendingOperation, settled)) {
        _pendingOperation = null;
      }
    }
  }

  Future<void> close({required Duration timeout}) {
    requirePositiveDuration(timeout, 'timeout');
    if (_pendingOperation != null) {
      throw StateError('随机访问文件仍有操作未结束，无法关闭。');
    }
    _cleanupRequested = true;
    return _releaseFile().timeout(
      timeout,
      onTimeout: () => throw TimeoutException('随机访问文件关闭超时。', timeout),
    );
  }

  /// 空闲时立即释放；超时操作仍在执行时，待其结束后只安排一次释放。
  /// 清理异常不会覆盖调用方的主要结果。
  Future<void> cleanup() async {
    _cleanupRequested = true;
    final pending = _pendingOperation;
    if (pending != null) {
      if (!_lateReleaseScheduled) {
        _lateReleaseScheduled = true;
        unawaited(_releaseAfterPending(pending));
      }
      return;
    }
    try {
      await _releaseFile().timeout(_cleanupTimeout);
    } catch (_) {
      // 清理异常不能覆盖主要文件错误或超时错误。
    }
  }

  Future<void> _releaseAfterPending(Future<void> pending) async {
    await pending;
    _pendingOperation = null;
    try {
      await _releaseFile().timeout(_cleanupTimeout);
    } catch (_) {
      // 原操作已经超时。
    }
  }

  Future<void> _releaseFile() {
    final active = _releaseFuture;
    if (active != null) return active;
    final completer = Completer<void>();
    final future = completer.future;
    _releaseFuture = future;
    unawaited(
      Future<void>.sync(() => _release?.call(file) ?? file.close()).then<void>(
        (_) => completer.complete(),
        onError: completer.completeError,
      ),
    );
    return future;
  }
}

/// 在限定时间内打开随机访问文件；打开操作延迟完成时自动关闭句柄。
Future<BoundedRandomAccessFileLease> openBoundedRandomAccessFileLease(
  File file, {
  required FileMode mode,
  required Duration timeout,
  bool deleteIfOpenCompletesLate = false,
  Future<void> Function(RandomAccessFile file)? release,
}) async {
  requirePositiveDuration(timeout, 'timeout');
  final openFuture = file.open(mode: mode);
  try {
    final opened = await openFuture.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('打开文件超过时限。', timeout),
    );
    return BoundedRandomAccessFileLease(opened, release: release);
  } on TimeoutException {
    unawaited(
      _cleanupLateOpenedFile(
        file,
        openFuture,
        timeout: timeout,
        deleteFile: deleteIfOpenCompletesLate,
        release: release,
      ),
    );
    rethrow;
  }
}

Future<void> _cleanupLateOpenedFile(
  File file,
  Future<RandomAccessFile> openFuture, {
  required Duration timeout,
  required bool deleteFile,
  required Future<void> Function(RandomAccessFile file)? release,
}) async {
  try {
    final opened = await openFuture;
    final releaseFuture = Future<void>.sync(
      () => release?.call(opened) ?? opened.close(),
    );
    try {
      await releaseFuture.timeout(timeout);
    } on TimeoutException {
      if (deleteFile) {
        unawaited(
          releaseFuture.then<void>(
            (_) => _deleteTemporaryFileAfterWriteFailure(
              file,
              onSecondaryError: null,
            ),
            onError: (Object _, StackTrace _) {},
          ),
        );
      }
      return;
    }
    if (deleteFile) {
      await _deleteTemporaryFileAfterWriteFailure(file, onSecondaryError: null);
    }
  } catch (_) {
    // 调用方已收到主要错误，延迟清理失败不能覆盖原始结果。
  }
}

/// 本地文件载入内存时可确定识别的安全失败。
final class BoundedFileReadException implements IOException {
  const BoundedFileReadException({
    required this.filePath,
    required this.maxBytes,
    required this.failure,
  });

  final String filePath;
  final int maxBytes;
  final BoundedFileReadFailure failure;

  @override
  String toString() {
    return switch (failure) {
      BoundedFileReadFailure.tooLarge =>
        '文件超过 ${formatByteSize(maxBytes)} 读取上限：$filePath',
      BoundedFileReadFailure.changedDuringRead => '文件在读取期间发生变化：$filePath',
    };
  }
}

/// 同步读取小型普通文件，并在同一句柄上限制和复核长度。
///
/// 仅用于必须同步返回的轻量状态探测；大文件和业务 I/O 应使用异步版本。
Uint8List readBoundedFileBytesSync(
  File file, {
  required int maxBytes,
  bool verifyUnchanged = true,
}) {
  requirePositiveInt(maxBytes, 'maxBytes');
  final initialStat = file.statSync();
  if (!isRegularFileStat(initialStat)) {
    throw FileSystemException('路径不是普通文件。', file.path);
  }
  if (initialStat.size < 0 || initialStat.size > maxBytes) {
    throw BoundedFileReadException(
      filePath: file.path,
      maxBytes: maxBytes,
      failure: BoundedFileReadFailure.tooLarge,
    );
  }

  RandomAccessFile? input;
  try {
    input = file.openSync();
    final initialLength = input.lengthSync();
    if (initialLength < 0 || initialLength > maxBytes) {
      throw BoundedFileReadException(
        filePath: file.path,
        maxBytes: maxBytes,
        failure: BoundedFileReadFailure.tooLarge,
      );
    }
    final bytes = Uint8List(initialLength);
    var offset = 0;
    while (offset < initialLength) {
      final read = input.readIntoSync(bytes, offset, initialLength);
      if (read <= 0) break;
      offset += read;
    }
    if (offset != initialLength || input.lengthSync() != initialLength) {
      throw BoundedFileReadException(
        filePath: file.path,
        maxBytes: maxBytes,
        failure: BoundedFileReadFailure.changedDuringRead,
      );
    }
    if (verifyUnchanged) {
      final finalStat = file.statSync();
      if (!isRegularFileStat(finalStat) ||
          finalStat.size != initialLength ||
          finalStat.modified != initialStat.modified ||
          finalStat.changed != initialStat.changed) {
        throw BoundedFileReadException(
          filePath: file.path,
          maxBytes: maxBytes,
          failure: BoundedFileReadFailure.changedDuringRead,
        );
      }
    }
    return bytes;
  } finally {
    input?.closeSync();
  }
}

/// 同步读取并解码小型有界文本文件。
String readBoundedFileStringSync(
  File file, {
  required int maxBytes,
  Encoding encoding = utf8,
  bool verifyUnchanged = true,
}) => encoding.decode(
  readBoundedFileBytesSync(
    file,
    maxBytes: maxBytes,
    verifyUnchanged: verifyUnchanged,
  ),
);

/// 以大小、空闲时限和总时限约束读取普通本地文件。
///
/// 长度检查与读取共用一个句柄，缩小状态检查与使用间隙；默认在读取后复核
/// 路径元数据，拒绝读取期间发生变化的文件。
Future<Uint8List> readBoundedFileBytes(
  File file, {
  required int maxBytes,
  required Duration idleTimeout,
  required Duration totalTimeout,
  bool verifyUnchanged = true,
  bool truncateToMaxBytes = false,
  BoundedFileHandleOwner? handleOwner,
}) async {
  requirePositiveInt(maxBytes, 'maxBytes');
  requirePositiveDuration(idleTimeout, 'idleTimeout');
  final deadline = MonotonicDeadline(
    totalTimeout,
    timeoutMessage: '文件读取超过总时限。',
  );

  BoundedRandomAccessFileLease? lease;
  try {
    final preflightStat = await file.stat().timeout(
      deadline.limit(idleTimeout),
    );
    if (!isRegularFileStat(preflightStat)) {
      throw FileSystemException('路径不是普通文件。', file.path);
    }
    final openFuture = file.open();
    if (handleOwner != null) {
      final input = await handleOwner.acquireFile(
        openFuture,
        timeout: deadline.limit(idleTimeout),
      );
      lease = BoundedRandomAccessFileLease(
        input,
        release: handleOwner.releaseFile,
      );
    } else {
      try {
        lease = BoundedRandomAccessFileLease(
          await openFuture.timeout(deadline.limit(idleTimeout)),
        );
      } on TimeoutException {
        unawaited(_closeLateFile(openFuture));
        rethrow;
      }
    }
    final activeLease = lease;

    final initialStat = await file.stat().timeout(deadline.limit(idleTimeout));
    if (!isRegularFileStat(initialStat)) {
      throw FileSystemException('路径不是普通文件。', file.path);
    }
    final initialLength = await activeLease.run(
      (input) => input.length(),
      timeout: deadline.limit(idleTimeout),
    );
    if (initialLength < 0 ||
        (!truncateToMaxBytes && initialLength > maxBytes)) {
      throw BoundedFileReadException(
        filePath: file.path,
        maxBytes: maxBytes,
        failure: BoundedFileReadFailure.tooLarge,
      );
    }

    final retainedLength = initialLength < maxBytes ? initialLength : maxBytes;
    final bytes = Uint8List(retainedLength);
    var offset = 0;
    while (offset < retainedLength) {
      final end = offset + _boundedFileReadChunkBytes < retainedLength
          ? offset + _boundedFileReadChunkBytes
          : retainedLength;
      final read = await activeLease.run(
        (input) => input.readInto(bytes, offset, end),
        timeout: deadline.limit(idleTimeout),
      );
      if (read <= 0) {
        throw BoundedFileReadException(
          filePath: file.path,
          maxBytes: maxBytes,
          failure: BoundedFileReadFailure.changedDuringRead,
        );
      }
      offset += read;
    }

    final finalLength = await activeLease.run(
      (input) => input.length(),
      timeout: deadline.limit(idleTimeout),
    );
    if (finalLength != initialLength) {
      throw BoundedFileReadException(
        filePath: file.path,
        maxBytes: maxBytes,
        failure: BoundedFileReadFailure.changedDuringRead,
      );
    }

    if (verifyUnchanged) {
      final finalStat = await file.stat().timeout(deadline.limit(idleTimeout));
      if (!isRegularFileStat(finalStat) ||
          finalStat.size != initialLength ||
          finalStat.modified != initialStat.modified ||
          finalStat.changed != initialStat.changed) {
        throw BoundedFileReadException(
          filePath: file.path,
          maxBytes: maxBytes,
          failure: BoundedFileReadFailure.changedDuringRead,
        );
      }
    }

    await activeLease.close(timeout: deadline.limit(idleTimeout));
    lease = null;
    return bytes;
  } finally {
    deadline.stop();
    await lease?.cleanup();
  }
}

/// 从普通文件开头最多读取 [maxBytes] 字节。
///
/// 与 [readBoundedFileBytes] 不同，本方法允许更大的文件但只保留前缀，同时继续
/// 执行空闲时限、总时限、句柄和变更检查，适合大文件预览。
Future<Uint8List> readBoundedFilePrefixBytes(
  File file, {
  required int maxBytes,
  Duration idleTimeout = defaultBoundedFileReadIdleTimeout,
  Duration totalTimeout = defaultBoundedFileReadTotalTimeout,
  bool verifyUnchanged = true,
  BoundedFileHandleOwner? handleOwner,
}) {
  return readBoundedFileBytes(
    file,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
    verifyUnchanged: verifyUnchanged,
    truncateToMaxBytes: true,
    handleOwner: handleOwner,
  );
}

final class BoundedTextLineReadResult {
  const BoundedTextLineReadResult({
    required this.lines,
    required this.truncated,
  });

  final List<String> lines;
  final bool truncated;
}

/// 在文件前缀、行数、单行长度和时间限制内读取 UTF-8 行范围。
Future<BoundedTextLineReadResult> readBoundedUtf8Lines(
  File file, {
  required int startLine,
  required int maxLines,
  required int maxScanBytes,
  required int maxLineCharacters,
  Duration idleTimeout = defaultBoundedFileReadIdleTimeout,
  Duration totalTimeout = defaultBoundedFileReadTotalTimeout,
}) async {
  requirePositiveInt(startLine, 'startLine');
  requirePositiveInt(maxLines, 'maxLines');
  requirePositiveInt(maxScanBytes, 'maxScanBytes');
  requirePositiveInt(maxLineCharacters, 'maxLineCharacters');

  final bytes = await readBoundedFilePrefixBytes(
    file,
    maxBytes: maxScanBytes + 1,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  final scanLimitReached = bytes.length > maxScanBytes;
  final retainedBytes = scanLimitReached
      ? Uint8List.sublistView(bytes, 0, maxScanBytes)
      : bytes;
  final decoded = utf8.decode(retainedBytes, allowMalformed: true);
  final lines = <String>[];
  var lineNumber = 0;
  var truncated = scanLimitReached;
  for (final line in LineSplitter.split(decoded)) {
    lineNumber += 1;
    if (lineNumber < startLine) continue;
    if (lines.length >= maxLines) {
      truncated = true;
      break;
    }
    final clipped = clipText(line, maxLineCharacters, suffix: '');
    if (clipped.length != line.length) truncated = true;
    lines.add(clipped);
  }
  return BoundedTextLineReadResult(lines: lines, truncated: truncated);
}

/// 读取并解码有界文本文件，避免 [File.readAsString] 先把任意大小文件留在内存中。
Future<String> readBoundedFileString(
  File file, {
  required int maxBytes,
  Duration idleTimeout = defaultBoundedFileReadIdleTimeout,
  Duration totalTimeout = defaultBoundedFileReadTotalTimeout,
  Encoding encoding = utf8,
  bool verifyUnchanged = true,
  BoundedFileHandleOwner? handleOwner,
}) async {
  final bytes = await readBoundedFileBytes(
    file,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
    verifyUnchanged: verifyUnchanged,
    handleOwner: handleOwner,
  );
  return encoding.decode(bytes);
}

/// POSIX 平台区分普通文件与 FIFO、设备；Windows 保持可移植的
/// [FileSystemEntityType] 检查。
bool isRegularFileStat(FileStat stat) {
  if (stat.type != FileSystemEntityType.file) return false;
  if (Platform.isWindows) return true;
  return (stat.mode & _posixFileTypeMask) == _posixRegularFileType;
}

/// 有界检查普通文件是否存在；路径存在但不是普通文件时抛出异常，避免持久化逻辑
/// 把目录或其他特殊实体误判成“文件不存在”后继续覆盖。
Future<bool> regularFileExistsBounded(
  File file, {
  Duration timeout = defaultBoundedFileReadIdleTimeout,
  bool followLinks = true,
}) async {
  final type = await _fileSystemEntityTypeBounded(
    file.path,
    timeout: timeout,
    followLinks: followLinks,
  );
  if (type == FileSystemEntityType.notFound) return false;
  if (type == FileSystemEntityType.file) return true;
  throw FileSystemException('路径不是普通文件。', file.path);
}

/// 异步检查 [path] 是否为普通文件，可选择不跟随末级符号链接。元数据失败或超时
/// 视为文件不存在，使 UI 事件处理器能够安全失败而不阻塞主 isolate。
Future<bool> isRegularFilePath(
  String path, {
  Duration timeout = defaultBoundedFileReadIdleTimeout,
  bool followLinks = false,
}) async {
  return await probeFileSystemEntityType(
        path,
        timeout: timeout,
        followLinks: followLinks,
      ) ==
      FileSystemEntityType.file;
}

Future<FileSystemEntityType> probeFileSystemEntityType(
  String path, {
  Duration timeout = defaultBoundedFileReadIdleTimeout,
  bool followLinks = false,
}) async {
  if (path.trim().isEmpty) return FileSystemEntityType.notFound;
  requirePositiveDuration(timeout, 'timeout');
  try {
    return await _fileSystemEntityTypeBounded(
      path,
      timeout: timeout,
      followLinks: followLinks,
    );
  } on FileSystemException {
    return FileSystemEntityType.notFound;
  } on TimeoutException {
    return FileSystemEntityType.notFound;
  } on ArgumentError {
    return FileSystemEntityType.notFound;
  }
}

Future<FileSystemEntityType> _fileSystemEntityTypeBounded(
  String path, {
  required Duration timeout,
  required bool followLinks,
}) {
  requirePositiveDuration(timeout, 'timeout');
  return FileSystemEntity.type(path, followLinks: followLinks).timeout(timeout);
}

Future<bool> isDirectoryPath(
  String path, {
  Duration timeout = defaultBoundedFileReadIdleTimeout,
  bool followLinks = false,
}) async {
  return await probeFileSystemEntityType(
        path,
        timeout: timeout,
        followLinks: followLinks,
      ) ==
      FileSystemEntityType.directory;
}

Future<void> _closeLateFile(Future<RandomAccessFile> openFuture) async {
  try {
    final input = await openFuture;
    await input.close().timeout(_boundedFileCleanupTimeout);
  } catch (_) {
    // 调用方已经收到超时，清理只做尽力处理。
  }
}
