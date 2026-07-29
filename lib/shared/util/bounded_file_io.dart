import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'argument_guards.dart';
import 'async_concurrency.dart';
import 'byte_size_format.dart';
import 'text_clip.dart';

const int _boundedFileReadChunkBytes = 64 * 1024;
const Duration _boundedFileCleanupTimeout = Duration(seconds: 2);
const Duration defaultBoundedFileReadIdleTimeout = Duration(seconds: 3);
const Duration defaultBoundedFileReadTotalTimeout = Duration(seconds: 10);
const int _posixFileTypeMask = 0xF000;
const int _posixRegularFileType = 0x8000;

enum BoundedFileReadFailure { tooLarge, changedDuringRead }

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

/// Serializes timed asynchronous operations on one [RandomAccessFile] and
/// defers release when a timed-out operation is still pending. Dart forbids a
/// second async operation (including close) on the same handle until the first
/// settles, so immediate cleanup after [Future.timeout] can otherwise leak the
/// handle permanently.
final class BoundedRandomAccessFileLease {
  BoundedRandomAccessFileLease(
    this.file, {
    Future<void> Function(RandomAccessFile file)? release,
    Duration cleanupTimeout = _boundedFileCleanupTimeout,
  }) : _release = release,
       _cleanupTimeout = cleanupTimeout {
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
      throw StateError('Random-access file lease is not available.');
    }
    final operationFuture = operation(file);
    final settled = operationFuture.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pendingOperation = settled;
    var deadlineExpired = false;
    try {
      return await operationFuture.timeout(
        timeout,
        onTimeout: () {
          deadlineExpired = true;
          throw TimeoutException(
            'Random-access file operation timed out.',
            timeout,
          );
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
      throw StateError(
        'Cannot close a random-access file while an operation is pending.',
      );
    }
    _cleanupRequested = true;
    return _releaseFile().timeout(timeout);
  }

  /// Releases now when idle, or schedules one release after a timed-out
  /// operation settles. Cleanup errors stay secondary to the caller's result.
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
      // Cleanup must not replace the primary file or timeout failure.
    }
  }

  Future<void> _releaseAfterPending(Future<void> pending) async {
    await pending;
    _pendingOperation = null;
    try {
      await _releaseFile().timeout(_cleanupTimeout);
    } catch (_) {
      // The original operation has already timed out.
    }
  }

  Future<void> _releaseFile() {
    return _releaseFuture ??= Future<void>.sync(
      () => _release?.call(file) ?? file.close(),
    );
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
    await (release?.call(opened) ?? opened.close()).timeout(timeout);
    if (deleteFile && await file.exists().timeout(timeout)) {
      await file.delete().timeout(timeout);
    }
  } catch (_) {
    // 调用方已收到主要错误，延迟清理失败不能覆盖原始结果。
  }
}

/// A deterministic safety failure while retaining a local file in memory.
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
        'File exceeds the ${formatByteSize(maxBytes)} read limit: $filePath',
      BoundedFileReadFailure.changedDuringRead =>
        'File changed while it was being read: $filePath',
    };
  }
}

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
      throw FileSystemException('Path is not a regular file.', file.path);
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
      throw FileSystemException('Path is not a regular file.', file.path);
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

/// Reads at most [maxBytes] from the start of a regular file.
///
/// Unlike [readBoundedFileBytes], a larger file is accepted and only its
/// prefix is retained. The same idle, total-time, handle, and mutation checks
/// still apply, making this suitable for large-file previews.
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

/// Reads and decodes a bounded text file without first allowing an arbitrary
/// file to be retained in memory by [File.readAsString].
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

/// Distinguishes regular files from FIFOs/devices on POSIX while preserving
/// the portable [FileSystemEntityType] check on Windows.
bool isRegularFileStat(FileStat stat) {
  if (stat.type != FileSystemEntityType.file) return false;
  if (Platform.isWindows) return true;
  return (stat.mode & _posixFileTypeMask) == _posixRegularFileType;
}

/// Asynchronously checks whether [path] is a regular file without following a
/// leaf symbolic link. Metadata failures and timeouts are treated as a missing
/// file so UI event handlers can fail closed without blocking the main isolate.
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
    return await FileSystemEntity.type(
      path,
      followLinks: followLinks,
    ).timeout(timeout);
  } on FileSystemException {
    return FileSystemEntityType.notFound;
  } on TimeoutException {
    return FileSystemEntityType.notFound;
  } on ArgumentError {
    return FileSystemEntityType.notFound;
  }
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
    // The caller has already received the timeout; cleanup stays best effort.
  }
}
