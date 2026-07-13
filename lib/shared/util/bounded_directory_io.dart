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
