import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';

const int webEngineMaxJsonFileBytes = 16 * kBytesPerMiB;
const int webEngineMaxPayloadFileBytes = 64 * kBytesPerMiB;
const int webEngineMaxIndexEntries = 10000;
const int webEngineMaxDirectoryEntries = 10000;
const Duration webEngineDirectoryIdleTimeout = Duration(seconds: 2);
const Duration webEngineDirectoryTotalTimeout = Duration(seconds: 15);
const Duration webEngineFileOperationTimeout = Duration(seconds: 2);

final RegExp _webEngineCacheKeyPattern = RegExp(r'^[0-9a-f]{64}$');

bool isValidWebEngineCacheKey(String key) {
  return _webEngineCacheKeyPattern.hasMatch(key);
}

String? webEngineCachePayloadFileName(String key) {
  return isValidWebEngineCacheKey(key) ? '$key.txt' : null;
}

Map<String, Object?> webEngineCacheEntriesFromValue(Object? value) {
  final raw = stringKeyedMapFromValue(value);
  final entries = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entries.length >= webEngineMaxIndexEntries) break;
    if (!isValidWebEngineCacheKey(entry.key)) continue;
    entries[entry.key] = entry.value;
  }
  return entries;
}

final class WebEngineIoDeadline {
  WebEngineIoDeadline({
    this.totalTimeout = webEngineDirectoryTotalTimeout,
    this.operationTimeout = webEngineFileOperationTimeout,
  }) : _stopwatch = Stopwatch()..start();

  final Duration totalTimeout;
  final Duration operationTimeout;
  final Stopwatch _stopwatch;

  Duration remaining() {
    final microseconds =
        totalTimeout.inMicroseconds - _stopwatch.elapsedMicroseconds;
    if (microseconds <= 0) {
      throw TimeoutException('Web engine filesystem operation timed out.');
    }
    return Duration(microseconds: microseconds);
  }

  Duration nextOperationTimeout() {
    final remainingTime = remaining();
    return remainingTime < operationTimeout ? remainingTime : operationTimeout;
  }

  void stop() => _stopwatch.stop();
}

Future<BoundedDirectoryListing> listWebEngineDirectoryBounded(
  Directory directory,
  WebEngineIoDeadline deadline, {
  bool recursive = false,
}) {
  final remainingTime = deadline.remaining();
  final idleTimeout = remainingTime < webEngineDirectoryIdleTimeout
      ? remainingTime
      : webEngineDirectoryIdleTimeout;
  return listDirectoryBounded(
    directory,
    maxEntries: webEngineMaxDirectoryEntries,
    recursive: recursive,
    idleTimeout: idleTimeout,
    totalTimeout: remainingTime,
  );
}

Future<BoundedDirectoryUsage> measureWebEngineDirectoryBounded(
  Directory directory,
) {
  return measureDirectoryBounded(
    directory,
    maxEntries: webEngineMaxDirectoryEntries,
    idleTimeout: webEngineDirectoryIdleTimeout,
    totalTimeout: webEngineDirectoryTotalTimeout,
    operationTimeout: webEngineFileOperationTimeout,
  );
}

/// Deletes only entries observed by a bounded, non-link-following scan.
/// Directories are removed deepest-first and non-recursively, so a truncated
/// scan cannot accidentally delete unvisited content.
Future<bool> clearWebEngineDirectoryBounded(Directory directory) async {
  final deadline = WebEngineIoDeadline();
  var complete = true;
  try {
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    ).timeout(deadline.nextOperationTimeout());
    if (type == FileSystemEntityType.notFound) return true;
    if (type != FileSystemEntityType.directory) return false;

    final listing = await listWebEngineDirectoryBounded(
      directory,
      deadline,
      recursive: true,
    );
    complete = !listing.truncated;
    final directories = <Directory>[];
    for (final entity in listing.entries) {
      if (entity is Directory) {
        directories.add(entity);
        continue;
      }
      try {
        await entity.delete().timeout(deadline.nextOperationTimeout());
      } on TimeoutException {
        complete = false;
        break;
      } on FileSystemException {
        complete = false;
      }
    }

    directories.sort((left, right) {
      final depthOrder = right.path.length.compareTo(left.path.length);
      return depthOrder != 0 ? depthOrder : right.path.compareTo(left.path);
    });
    for (final child in directories) {
      try {
        await child.delete().timeout(deadline.nextOperationTimeout());
      } on TimeoutException {
        complete = false;
        break;
      } on FileSystemException {
        complete = false;
      }
    }
    return complete;
  } on TimeoutException {
    return false;
  } on FileSystemException {
    return false;
  } finally {
    deadline.stop();
  }
}

Future<Object?> readWebEngineJsonFile(
  File file, {
  int maxBytes = webEngineMaxJsonFileBytes,
}) async {
  final raw = await readBoundedFileString(file, maxBytes: maxBytes);
  return jsonDecode(raw);
}

Future<String> readWebEnginePayloadFile(File file) {
  return readBoundedFileString(file, maxBytes: webEngineMaxPayloadFileBytes);
}

Future<void> writeWebEngineJsonFile(File file, Object? value) async {
  final content = jsonEncode(value);
  if (utf8.encode(content).length > webEngineMaxJsonFileBytes) {
    throw const FileSystemException(
      'Web engine JSON exceeds the 16 MiB persistence limit.',
    );
  }
  await writeFileAtomically(file, content);
}
