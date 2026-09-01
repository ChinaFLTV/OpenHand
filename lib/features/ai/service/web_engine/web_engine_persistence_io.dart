import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/argument_guards.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/hex_encoding.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/serial_task_queue.dart';

const int webEngineMaxJsonFileBytes = 16 * kBytesPerMiB;
const int webEngineMaxPayloadFileBytes = 64 * kBytesPerMiB;
const int webEngineMaxIndexEntries = 10000;
const int webEngineMaxDirectoryEntries = 10000;
const String webEngineCacheIndexFileName = 'index.json';
const String webEngineCachePayloadExtension = '.txt';
const Duration webEngineDirectoryIdleTimeout = Duration(seconds: 2);
const Duration webEngineDirectoryTotalTimeout = Duration(seconds: 15);
const Duration webEngineFileOperationTimeout = Duration(seconds: 2);

Future<void> runWebEngineSerializedOperation({
  required bool shuttingDown,
  required SerialTaskQueue queue,
  required String logTag,
  required String action,
  required Future<void> Function() operation,
}) async {
  if (shuttingDown) return;
  try {
    await queue.enqueue(operation);
  } catch (error, stack) {
    silentLog(logTag, action, error, stack);
  }
}

/// 缓存键即载荷内容的 SHA-256 摘要。
bool isValidWebEngineCacheKey(String key) {
  return isLowercaseSha256Hex(key);
}

String? webEngineCachePayloadFileName(String key) {
  return isValidWebEngineCacheKey(key)
      ? '$key$webEngineCachePayloadExtension'
      : null;
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
  }) : _deadline = MonotonicDeadline(
         totalTimeout,
         timeoutMessage: 'Web 引擎文件操作超过总时限。',
       ) {
    requirePositiveDuration(operationTimeout, 'operationTimeout');
  }

  final Duration totalTimeout;
  final Duration operationTimeout;
  final MonotonicDeadline _deadline;

  Duration remaining() => _deadline.remaining();

  Duration nextOperationTimeout() => _deadline.limit(operationTimeout);

  void stop() => _deadline.stop();
}

Future<bool> webEngineEntityExists(
  FileSystemEntity entity, {
  WebEngineIoDeadline? deadline,
}) {
  return entity.exists().timeout(
    deadline?.nextOperationTimeout() ?? webEngineFileOperationTimeout,
  );
}

Future<void> ensureWebEngineDirectory(
  Directory directory, {
  WebEngineIoDeadline? deadline,
}) async {
  if (await webEngineEntityExists(directory, deadline: deadline)) return;
  await directory
      .create(recursive: true)
      .timeout(
        deadline?.nextOperationTimeout() ?? webEngineFileOperationTimeout,
      );
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
  Directory directory, {
  WebEngineIoDeadline? deadline,
}) {
  final totalTimeout = deadline?.remaining() ?? webEngineDirectoryTotalTimeout;
  final idleTimeout = totalTimeout < webEngineDirectoryIdleTimeout
      ? totalTimeout
      : webEngineDirectoryIdleTimeout;
  final operationTimeout =
      deadline?.nextOperationTimeout() ?? webEngineFileOperationTimeout;
  return measureDirectoryBounded(
    directory,
    maxEntries: webEngineMaxDirectoryEntries,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
    operationTimeout: operationTimeout,
  );
}

/// 仅删除有界且不跟随链接的扫描实际发现的条目。
/// 目录按深度倒序进行非递归删除，扫描截断时不会误删未访问内容。
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
  WebEngineIoDeadline? deadline,
}) async {
  final totalTimeout = deadline?.remaining() ?? webEngineDirectoryTotalTimeout;
  final idleTimeout =
      deadline?.nextOperationTimeout() ?? webEngineFileOperationTimeout;
  final raw = await readBoundedFileString(
    file,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  return jsonDecode(raw);
}

Future<Object?> readWebEngineJsonFileIfExists(
  File file, {
  int maxBytes = webEngineMaxJsonFileBytes,
  WebEngineIoDeadline? deadline,
}) async {
  final effectiveDeadline = deadline ?? WebEngineIoDeadline();
  try {
    if (!await webEngineEntityExists(file, deadline: effectiveDeadline)) {
      return null;
    }
    return await readWebEngineJsonFile(
      file,
      maxBytes: maxBytes,
      deadline: effectiveDeadline,
    );
  } finally {
    if (deadline == null) effectiveDeadline.stop();
  }
}

Future<String> readWebEnginePayloadFile(
  File file, {
  WebEngineIoDeadline? deadline,
}) {
  final totalTimeout = deadline?.remaining() ?? webEngineDirectoryTotalTimeout;
  final idleTimeout =
      deadline?.nextOperationTimeout() ?? webEngineFileOperationTimeout;
  return readBoundedFileString(
    file,
    maxBytes: webEngineMaxPayloadFileBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
}

Future<void> writeWebEngineJsonFile(File file, Object? value) async {
  final content = jsonEncode(value);
  if (utf8.encode(content).length > webEngineMaxJsonFileBytes) {
    throw const FileSystemException('Web 引擎 JSON 超过 16 MiB 持久化上限。');
  }
  await writeFileAtomically(file, content);
}
