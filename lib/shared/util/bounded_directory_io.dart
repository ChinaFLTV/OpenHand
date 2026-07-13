import 'dart:async';
import 'dart:io';

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
  if (maxEntries < 1) {
    throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive.');
  }
  if (idleTimeout <= Duration.zero || totalTimeout <= Duration.zero) {
    throw ArgumentError('Directory listing timeouts must be positive.');
  }

  final entries = <FileSystemEntity>[];
  final stopwatch = Stopwatch()..start();
  var truncated = false;
  try {
    await for (final entry
        in directory
            .list(recursive: recursive, followLinks: followLinks)
            .timeout(idleTimeout)) {
      if (stopwatch.elapsed >= totalTimeout || entries.length >= maxEntries) {
        truncated = true;
        break;
      }
      entries.add(entry);
    }
  } on TimeoutException {
    truncated = true;
  } finally {
    stopwatch.stop();
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
  if (maxEntries < 1) {
    throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive.');
  }
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
  final stopwatch = Stopwatch()..start();
  try {
    await for (final entry
        in directory
            .list(recursive: recursive, followLinks: followLinks)
            .timeout(idleTimeout)) {
      if (stopwatch.elapsed >= totalTimeout || scannedEntries >= maxEntries) {
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

      final remaining = totalTimeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        truncated = true;
        break;
      }
      final timeout = remaining < operationTimeout
          ? remaining
          : operationTimeout;
      try {
        final stat = await entry.stat().timeout(timeout);
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
    stopwatch.stop();
  }
  return BoundedDirectoryUsage(
    totalBytes: totalBytes,
    fileCount: fileCount,
    directoryCount: directoryCount,
    scannedEntries: scannedEntries,
    truncated: truncated,
  );
}
