import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'byte_size_format.dart';

const int _boundedFileReadChunkBytes = 64 * 1024;
const Duration _boundedFileCleanupTimeout = Duration(seconds: 2);
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

  RandomAccessFile? input;
  Future<void>? closeFuture;
  try {
    final preflightStat = await file.stat().timeout(nextOperationTimeout());
    if (!_isRegularFile(preflightStat)) {
      throw FileSystemException('Path is not a regular file.', file.path);
    }
    final openFuture = file.open();
    if (handleOwner != null) {
      input = await handleOwner.acquireFile(
        openFuture,
        timeout: nextOperationTimeout(),
      );
    } else {
      try {
        input = await openFuture.timeout(nextOperationTimeout());
      } on TimeoutException {
        unawaited(_closeLateFile(openFuture));
        rethrow;
      }
    }

    final initialStat = await file.stat().timeout(nextOperationTimeout());
    if (!_isRegularFile(initialStat)) {
      throw FileSystemException('Path is not a regular file.', file.path);
    }
    final initialLength = await input.length().timeout(nextOperationTimeout());
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
      final read = await input
          .readInto(bytes, offset, end)
          .timeout(nextOperationTimeout());
      if (read <= 0) {
        throw BoundedFileReadException(
          filePath: file.path,
          maxBytes: maxBytes,
          failure: BoundedFileReadFailure.changedDuringRead,
        );
      }
      offset += read;
    }

    final finalLength = await input.length().timeout(nextOperationTimeout());
    if (finalLength != initialLength) {
      throw BoundedFileReadException(
        filePath: file.path,
        maxBytes: maxBytes,
        failure: BoundedFileReadFailure.changedDuringRead,
      );
    }

    if (verifyUnchanged) {
      final finalStat = await file.stat().timeout(nextOperationTimeout());
      if (!_isRegularFile(finalStat) ||
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

    final activeInput = input;
    closeFuture = handleOwner?.releaseFile(activeInput) ?? activeInput.close();
    await closeFuture.timeout(nextOperationTimeout());
    input = null;
    closeFuture = null;
    return bytes;
  } finally {
    stopwatch.stop();
    final activeInput = input;
    if (activeInput != null) {
      try {
        await (closeFuture ??
                handleOwner?.releaseFile(activeInput) ??
                activeInput.close())
            .timeout(_boundedFileCleanupTimeout);
      } catch (_) {
        // Preserve the primary file, size, or timeout error.
      }
    }
  }
}

bool _isRegularFile(FileStat stat) {
  if (stat.type != FileSystemEntityType.file) return false;
  if (Platform.isWindows) return true;
  return (stat.mode & _posixFileTypeMask) == _posixRegularFileType;
}

Future<void> _closeLateFile(Future<RandomAccessFile> openFuture) async {
  try {
    final input = await openFuture;
    await input.close().timeout(_boundedFileCleanupTimeout);
  } catch (_) {
    // The caller has already received the timeout; cleanup stays best effort.
  }
}
