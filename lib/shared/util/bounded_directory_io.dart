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

/// Lists a directory without retaining an unbounded number of filesystem
/// entries or waiting indefinitely for a stalled filesystem.
Future<BoundedDirectoryListing> listDirectoryBounded(
  Directory directory, {
  required int maxEntries,
  bool recursive = false,
  bool followLinks = false,
  Duration idleTimeout = defaultBoundedDirectoryIdleTimeout,
  Duration totalTimeout = defaultBoundedDirectoryTotalTimeout,
}) async {
  requirePositiveInt(maxEntries, 'maxEntries');
  if (idleTimeout <= Duration.zero || totalTimeout <= Duration.zero) {
    throw ArgumentError('Directory listing timeouts must be positive.');
  }

  final entries = <FileSystemEntity>[];
  final deadline = MonotonicDeadline(
    totalTimeout,
    timeoutMessage: '目录扫描超过总时限。',
  );
  var truncated = false;
  try {
    await for (final entry
        in directory
            .list(recursive: recursive, followLinks: followLinks)
            .timeout(idleTimeout)) {
      if (deadline.isExpired || entries.length >= maxEntries) {
        truncated = true;
        break;
      }
      entries.add(entry);
    }
  } on TimeoutException {
    truncated = true;
  } finally {
    deadline.stop();
  }
  return BoundedDirectoryListing(
    entries: List<FileSystemEntity>.unmodifiable(entries),
    truncated: truncated,
  );
}

/// Measures directory usage without retaining every filesystem entry or
/// allowing a slow filesystem operation to block indefinitely.
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
  if (idleTimeout <= Duration.zero ||
      totalTimeout <= Duration.zero ||
      operationTimeout <= Duration.zero) {
    throw ArgumentError('Directory measurement timeouts must be positive.');
  }

  var totalBytes = 0;
  var fileCount = 0;
  var directoryCount = 0;
  var scannedEntries = 0;
  var truncated = false;
  final deadline = MonotonicDeadline(
    totalTimeout,
    timeoutMessage: '目录统计超过总时限。',
  );
  try {
    await for (final entry
        in directory
            .list(recursive: recursive, followLinks: followLinks)
            .timeout(idleTimeout)) {
      if (deadline.isExpired || scannedEntries >= maxEntries) {
        truncated = true;
        break;
      }
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
  }
  return BoundedDirectoryUsage(
    totalBytes: totalBytes,
    fileCount: fileCount,
    directoryCount: directoryCount,
    scannedEntries: scannedEntries,
    truncated: truncated,
  );
}
