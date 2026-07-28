import 'dart:async';
import 'dart:io';

import 'argument_guards.dart';
import 'async_concurrency.dart';

const Duration defaultBoundedDirectoryIdleTimeout = Duration(seconds: 3);
const Duration defaultBoundedDirectoryTotalTimeout = Duration(seconds: 10);

class BoundedDirectoryListing {
  const BoundedDirectoryListing({
    required this.entries,
    required this.truncated,
  });

  final List<FileSystemEntity> entries;
  final bool truncated;
}

class BoundedDirectoryUsage {
  const BoundedDirectoryUsage({
    required this.totalBytes,
    required this.fileCount,
    required this.directoryCount,
    required this.scannedEntries,
    required this.truncated,
  });

  final int totalBytes;
  final int fileCount;
  final int directoryCount;
  final int scannedEntries;
  final bool truncated;
}

/// 有界枚举目录，避免保留无限条目或被停滞的文件系统永久阻塞。
Future<BoundedDirectoryListing> listDirectoryBounded(
  Directory directory, {
  required int maxEntries,
  bool recursive = false,
  bool followLinks = false,
  Duration idleTimeout = defaultBoundedDirectoryIdleTimeout,
  Duration totalTimeout = defaultBoundedDirectoryTotalTimeout,
}) async {
  requirePositiveInt(maxEntries, 'maxEntries');
  requirePositiveDuration(idleTimeout, 'idleTimeout');
  requirePositiveDuration(totalTimeout, 'totalTimeout');

  final entries = <FileSystemEntity>[];
  final iterator = StreamIterator<FileSystemEntity>(
    directory.list(recursive: recursive, followLinks: followLinks),
  );
  final deadline = MonotonicDeadline(
    totalTimeout,
    timeoutMessage: '目录扫描超过总时限。',
  );
  var truncated = false;
  try {
    while (true) {
      final waitTimeout = deadline.limit(idleTimeout);
      if (!await iterator.moveNext().timeout(waitTimeout)) break;
      if (entries.length >= maxEntries) {
        truncated = true;
        break;
      }
      entries.add(iterator.current);
    }
  } on TimeoutException {
    truncated = true;
  } finally {
    deadline.stop();
    await runAsyncCleanupBounded(iterator.cancel);
  }
  return BoundedDirectoryListing(
    entries: List<FileSystemEntity>.unmodifiable(entries),
    truncated: truncated,
  );
}

/// 有界统计目录占用，避免保留全部条目或被缓慢文件系统永久阻塞。
Future<BoundedDirectoryUsage> measureDirectoryBounded(
  Directory directory, {
  required int maxEntries,
  bool recursive = true,
  bool followLinks = false,
  Duration idleTimeout = defaultBoundedDirectoryIdleTimeout,
  Duration totalTimeout = defaultBoundedDirectoryTotalTimeout,
  Duration operationTimeout = defaultBoundedDirectoryIdleTimeout,
}) async {
  requirePositiveInt(maxEntries, 'maxEntries');
  requirePositiveDuration(idleTimeout, 'idleTimeout');
  requirePositiveDuration(totalTimeout, 'totalTimeout');
  requirePositiveDuration(operationTimeout, 'operationTimeout');

  var totalBytes = 0;
  var fileCount = 0;
  var directoryCount = 0;
  var scannedEntries = 0;
  var truncated = false;
  final iterator = StreamIterator<FileSystemEntity>(
    directory.list(recursive: recursive, followLinks: followLinks),
  );
  final deadline = MonotonicDeadline(
    totalTimeout,
    timeoutMessage: '目录统计超过总时限。',
  );
  try {
    while (true) {
      final waitTimeout = deadline.limit(idleTimeout);
      if (!await iterator.moveNext().timeout(waitTimeout)) break;
      if (scannedEntries >= maxEntries) {
        truncated = true;
        break;
      }
      final entry = iterator.current;
      scannedEntries += 1;
      if (entry is Directory) {
        directoryCount += 1;
        continue;
      }
      if (entry is! File) {
        continue;
      }

      try {
        final stat = await entry.stat().timeout(
          deadline.limit(operationTimeout),
        );
        if (stat.type == FileSystemEntityType.file) {
          totalBytes += stat.size;
          fileCount += 1;
        }
      } on TimeoutException {
        truncated = true;
        break;
      } on FileSystemException {
        truncated = true;
      }
    }
  } on TimeoutException {
    truncated = true;
  } on FileSystemException {
    truncated = true;
  } finally {
    deadline.stop();
    await runAsyncCleanupBounded(iterator.cancel);
  }
  return BoundedDirectoryUsage(
    totalBytes: totalBytes,
    fileCount: fileCount,
    directoryCount: directoryCount,
    scannedEntries: scannedEntries,
    truncated: truncated,
  );
}
