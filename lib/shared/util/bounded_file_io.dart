import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'byte_size_format.dart';

const int _boundedFileReadChunkBytes = 64 * 1024;
const Duration _boundedFileCleanupTimeout = Duration(seconds: 2);
const Duration defaultBoundedFileReadIdleTimeout = Duration(seconds: 3);
const Duration defaultBoundedFileReadTotalTimeout = Duration(seconds: 10);
const int _posixFileTypeMask = 0xF000;
const int _posixRegularFileType = 0x8000;

enum BoundedFileReadFailure { tooLarge, changedDuringRead }

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
    if (cleanupTimeout <= Duration.zero) {
      throw ArgumentError.value(
        cleanupTimeout,
        'cleanupTimeout',
        'Must be positive.',
      );
    }
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
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
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
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
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

/// Reads a regular local file with per-file, idle, and total-time bounds.
///
/// A single open handle is used for the length check and all reads, closing the
/// stat/open TOCTOU gap. By default path metadata is checked again after the
/// read to reject in-place changes while retaining a coherent bounded payload.
Future<Uint8List> readBoundedFileBytes(
  File file, {
  required int maxBytes,
  required Duration idleTimeout,
  required Duration totalTimeout,
  bool verifyUnchanged = true,
  BoundedFileHandleOwner? handleOwner,
}) async {
  if (maxBytes < 1) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
  }
  if (idleTimeout <= Duration.zero) {
    throw ArgumentError.value(idleTimeout, 'idleTimeout', 'Must be positive.');
  }
  if (totalTimeout <= Duration.zero) {
    throw ArgumentError.value(
      totalTimeout,
      'totalTimeout',
      'Must be positive.',
    );
  }

  final stopwatch = Stopwatch()..start();
  Duration remainingBudget() {
    final remaining =
        totalTimeout.inMicroseconds - stopwatch.elapsedMicroseconds;
    if (remaining <= 0) {
      throw TimeoutException('File read exceeded its total time limit.');
    }
    return Duration(microseconds: remaining);
  }

  Duration nextOperationTimeout() {
    final remaining = remainingBudget();
    return remaining < idleTimeout ? remaining : idleTimeout;
  }

  BoundedRandomAccessFileLease? lease;
  try {
    final preflightStat = await file.stat().timeout(nextOperationTimeout());
    if (!isRegularFileStat(preflightStat)) {
      throw FileSystemException('Path is not a regular file.', file.path);
    }
    final openFuture = file.open();
    if (handleOwner != null) {
      final input = await handleOwner.acquireFile(
        openFuture,
        timeout: nextOperationTimeout(),
      );
      lease = BoundedRandomAccessFileLease(
        input,
        release: handleOwner.releaseFile,
      );
    } else {
      try {
        lease = BoundedRandomAccessFileLease(
          await openFuture.timeout(nextOperationTimeout()),
        );
      } on TimeoutException {
        unawaited(_closeLateFile(openFuture));
        rethrow;
      }
    }
    final activeLease = lease;

    final initialStat = await file.stat().timeout(nextOperationTimeout());
    if (!isRegularFileStat(initialStat)) {
      throw FileSystemException('Path is not a regular file.', file.path);
    }
    final initialLength = await activeLease.run(
      (input) => input.length(),
      timeout: nextOperationTimeout(),
    );
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
      final end = offset + _boundedFileReadChunkBytes < initialLength
          ? offset + _boundedFileReadChunkBytes
          : initialLength;
      final read = await activeLease.run(
        (input) => input.readInto(bytes, offset, end),
        timeout: nextOperationTimeout(),
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
      timeout: nextOperationTimeout(),
    );
    if (finalLength != initialLength) {
      throw BoundedFileReadException(
        filePath: file.path,
        maxBytes: maxBytes,
        failure: BoundedFileReadFailure.changedDuringRead,
      );
    }

    if (verifyUnchanged) {
      final finalStat = await file.stat().timeout(nextOperationTimeout());
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

    await activeLease.close(timeout: nextOperationTimeout());
    lease = null;
    return bytes;
  } finally {
    stopwatch.stop();
    await lease?.cleanup();
  }
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

/// Synchronous counterpart for startup paths that cannot become asynchronous.
///
/// The file is read through one fixed-size buffer after validating that it is
/// regular and within [maxBytes]. A length or metadata change is rejected so a
/// growing file cannot bypass the preflight size check.
String readBoundedFileStringSync(
  File file, {
  required int maxBytes,
  Encoding encoding = utf8,
  bool verifyUnchanged = true,
}) {
  if (maxBytes < 1) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
  }

  final initialStat = file.statSync();
  if (!isRegularFileStat(initialStat)) {
    throw FileSystemException('Path is not a regular file.', file.path);
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
      if (read <= 0) {
        throw BoundedFileReadException(
          filePath: file.path,
          maxBytes: maxBytes,
          failure: BoundedFileReadFailure.changedDuringRead,
        );
      }
      offset += read;
    }
    if (input.lengthSync() != initialLength) {
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
    return encoding.decode(bytes);
  } finally {
    input?.closeSync();
  }
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
}) {
  return _isFileSystemEntityPathType(
    path,
    expected: FileSystemEntityType.file,
    timeout: timeout,
    followLinks: followLinks,
  );
}

Future<bool> isDirectoryPath(
  String path, {
  Duration timeout = defaultBoundedFileReadIdleTimeout,
  bool followLinks = false,
}) {
  return _isFileSystemEntityPathType(
    path,
    expected: FileSystemEntityType.directory,
    timeout: timeout,
    followLinks: followLinks,
  );
}

Future<bool> _isFileSystemEntityPathType(
  String path, {
  required FileSystemEntityType expected,
  required Duration timeout,
  required bool followLinks,
}) async {
  if (path.trim().isEmpty) return false;
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
  }
  try {
    return await FileSystemEntity.type(
          path,
          followLinks: followLinks,
        ).timeout(timeout) ==
        expected;
  } on FileSystemException {
    return false;
  } on TimeoutException {
    return false;
  } on ArgumentError {
    return false;
  }
}

Future<void> _closeLateFile(Future<RandomAccessFile> openFuture) async {
  try {
    final input = await openFuture;
    await input.close().timeout(_boundedFileCleanupTimeout);
  } catch (_) {
    // The caller has already received the timeout; cleanup stays best effort.
  }
}
