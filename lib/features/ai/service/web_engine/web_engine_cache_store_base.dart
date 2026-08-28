import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/serial_task_queue.dart';
import 'web_engine_json_utils.dart';
import 'web_engine_persistence_io.dart';
import 'web_engine_value_parsing.dart';

/// WebSearch / WebFetch 共用的「prewarm/cleanup 报告」数据。
class WebEngineCachePrewarmReport {
  const WebEngineCachePrewarmReport({
    required this.removedExpired,
    required this.removedOrphanFiles,
    required this.removedOrphanEntries,
  });

  static const empty = WebEngineCachePrewarmReport(
    removedExpired: 0,
    removedOrphanFiles: 0,
    removedOrphanEntries: 0,
  );

  final int removedExpired;
  final int removedOrphanFiles;
  final int removedOrphanEntries;

  bool get isEmpty =>
      removedExpired == 0 &&
      removedOrphanFiles == 0 &&
      removedOrphanEntries == 0;
}

/// 基础原始命中：包含 payload 文本 + 元数据 + 时间戳。
///
/// 子类基于本结构包装出 `summary` / `content` 等典型字段命名。
class WebEngineCacheRawLookup {
  const WebEngineCacheRawLookup({
    required this.payload,
    required this.metadata,
    required this.cachedAt,
    required this.expiresAt,
  });

  final String payload;
  final Map<String, Object?> metadata;
  final DateTime cachedAt;
  final DateTime expiresAt;
}

/// WebSearch / WebFetch 缓存目录的公共骨架：
///
/// * 单实例 → 有界串行写盘队列，避免 index.json 互踩和任务无限堆积
/// * 目录 = `<openhand_cache>/<subdir>`，由子类指定 [subdir]
/// * 单条 entry 写在 `<key>.txt`，metadata 写在 `index.json` 的 `entries[key]` 中
/// * 子类只需声明：
///   * 三个 entry 字段名（`*_path/*_bytes/*_chars`）
///   * 取出 `cacheEnabled / cacheTtlSeconds / cacheMaxBytes` 的 `TSettings` 适配
///   * `logTag`（用于 silentLog 上下文）
abstract class WebEngineCacheStoreBase<TSettings> {
  static const Duration runtimeCleanupTimeout =
      kOpenHandServiceRuntimeCleanupTimeout;

  /// 子目录名（`web_search` / `web_fetch`）。
  String get subdir;

  /// 用于 silentLog 的命名空间。
  String get logTag;

  /// index entry 中存放相对文件名（payload）的字段名。
  String get payloadPathField;

  /// index entry 中存放 payload 字节数的字段名。
  String get payloadBytesField;

  /// index entry 中存放 payload 字符数的字段名。
  String get payloadCharsField;

  bool isCacheEnabled(TSettings settings);
  int cacheTtlSeconds(TSettings settings);
  int cacheMaxBytes(TSettings settings);

  final SerialTaskQueue _operations = SerialTaskQueue(
    maxPendingTasks: _maxPendingOperations,
  );
  static const int _maxPendingOperations = 64;
  final OpenHandAsyncOnce _shutdownOnce = OpenHandAsyncOnce();
  bool _shuttingDown = false;

  /// 默认缓存目录路径。
  String defaultDirectoryPath() =>
      p.join(OpenHandPaths.defaultCacheDirectoryPath(), subdir);

  /// 计算当前缓存目录的总字节数（含 index）。
  Future<int> totalBytesOnDisk() async {
    if (_shuttingDown) return 0;
    final dir = Directory(defaultDirectoryPath());
    final deadline = WebEngineIoDeadline();
    try {
      if (!await webEngineEntityExists(dir, deadline: deadline)) return 0;
      final usage = await measureWebEngineDirectoryBounded(
        dir,
        deadline: deadline,
      );
      if (usage.truncated) {
        silentLog(
          logTag,
          '统计磁盘总字节数',
          StateError('Web 引擎缓存空间统计已达到安全上限。'),
          StackTrace.current,
        );
      }
      return usage.totalBytes;
    } catch (error, stack) {
      silentLog(logTag, '统计磁盘总字节数', error, stack);
      return 0;
    } finally {
      deadline.stop();
    }
  }

  /// 用于全局「应用数据 → 数据清理」直接调用：清空整个目录。
  Future<void> clearAll() {
    if (_shuttingDown) return Future<void>.value();
    return _runSerialized('清理全部缓存', () async {
      final dir = Directory(defaultDirectoryPath());
      final complete = await clearWebEngineDirectoryBounded(dir);
      if (!complete) {
        throw StateError('Web 引擎缓存清理已达到安全上限。');
      }
    });
  }

  /// 应用启动后的「缓存预热 / 自愈」：扫描磁盘并重建 index.json。
  ///
  /// * 删除已过期条目（含其 .txt 文件）。
  /// * 删除磁盘上 .txt 文件已丢失的孤儿条目。
  /// * 删除 index 未登记的孤儿 .txt 文件。
  Future<WebEngineCachePrewarmReport> prewarm() async {
    if (_shuttingDown) return WebEngineCachePrewarmReport.empty;
    try {
      return await _operations.enqueue(() async {
        var removedExpired = 0;
        var removedOrphanFiles = 0;
        var removedOrphanEntries = 0;
        final deadline = WebEngineIoDeadline();
        try {
          final dir = Directory(defaultDirectoryPath());
          if (!await webEngineEntityExists(dir, deadline: deadline)) {
            return WebEngineCachePrewarmReport.empty;
          }
          final indexFile = File(p.join(dir.path, webEngineCacheIndexFileName));
          Map<String, Object?> root = <String, Object?>{};
          try {
            final decoded = await readWebEngineJsonFileIfExists(
              indexFile,
              deadline: deadline,
            );
            if (decoded is Map) root = stringKeyedMapFromValue(decoded);
          } on FormatException {
            /* 索引损坏时按空索引处理。 */
          }
          final entries = webEngineCacheEntriesFromValue(root['entries']);

          final now = DateTime.now().millisecondsSinceEpoch;
          final keysToRemove = <String>[];
          final keepFileNames = <String>{webEngineCacheIndexFileName};
          for (final entry in entries.entries) {
            final value = entry.value;
            if (value is! Map) {
              keysToRemove.add(entry.key);
              continue;
            }
            final expiresAt = webEngineNonNegativeIntFromValue(
              value['expires_at'],
            );
            final payloadRel = '${value[payloadPathField] ?? ''}'.trim();
            final expectedPayload = webEngineCachePayloadFileName(entry.key);
            if (expectedPayload == null || payloadRel != expectedPayload) {
              keysToRemove.add(entry.key);
              removedOrphanEntries++;
              continue;
            }
            if (expiresAt <= now) {
              keysToRemove.add(entry.key);
              final f = File(p.join(dir.path, payloadRel));
              if (await webEngineEntityExists(f, deadline: deadline)) {
                try {
                  await f.delete().timeout(deadline.nextOperationTimeout());
                } on TimeoutException {
                  rethrow;
                } on FileSystemException {
                  /* 删除失败不影响其余缓存自愈。 */
                }
              }
              removedExpired++;
            } else {
              final f = File(p.join(dir.path, payloadRel));
              if (!await webEngineEntityExists(f, deadline: deadline)) {
                keysToRemove.add(entry.key);
                removedOrphanEntries++;
              } else {
                keepFileNames.add(payloadRel);
              }
            }
          }
          for (final k in keysToRemove) {
            entries.remove(k);
          }

          try {
            final listing = await listWebEngineDirectoryBounded(dir, deadline);
            if (!listing.truncated) {
              for (final entity in listing.entries) {
                if (entity is! File) continue;
                final name = p.basename(entity.path);
                if (keepFileNames.contains(name)) continue;
                if (!name.endsWith(webEngineCachePayloadExtension)) continue;
                try {
                  await entity.delete().timeout(
                    deadline.nextOperationTimeout(),
                  );
                  removedOrphanFiles++;
                } on TimeoutException {
                  rethrow;
                } on FileSystemException {
                  /* 删除失败不影响其余缓存自愈。 */
                }
              }
            }
          } on TimeoutException {
            rethrow;
          } on FileSystemException {
            /* 枚举失败时保留现有索引。 */
          }

          root['entries'] = entries;
          try {
            await writeWebEngineJsonFile(indexFile, jsonSafeMap(root));
          } catch (error, stack) {
            silentLog(logTag, '预热缓存并写入索引', error, stack);
          }
          return WebEngineCachePrewarmReport(
            removedExpired: removedExpired,
            removedOrphanFiles: removedOrphanFiles,
            removedOrphanEntries: removedOrphanEntries,
          );
        } finally {
          deadline.stop();
        }
      });
    } catch (error, stack) {
      silentLog(logTag, '预热缓存', error, stack);
      return WebEngineCachePrewarmReport.empty;
    }
  }

  // 供子类的强类型查询和写入逻辑调用。
  /// 命中查询：未启用 / 不存在 / 过期 / payload 文件丢失 → 全部返回 null。
  /// 命中后异步触发 `_touchAccess` 更新 last_accessed_at。
  Future<WebEngineCacheRawLookup?> baseLookup({
    required String key,
    required TSettings settings,
  }) async {
    if (_shuttingDown ||
        !isCacheEnabled(settings) ||
        !isValidWebEngineCacheKey(key)) {
      return null;
    }
    final deadline = WebEngineIoDeadline();
    try {
      final dir = Directory(defaultDirectoryPath());
      final indexFile = File(p.join(dir.path, webEngineCacheIndexFileName));
      final decoded = await readWebEngineJsonFileIfExists(
        indexFile,
        deadline: deadline,
      );
      if (decoded is! Map) return null;
      final entries = webEngineCacheEntriesFromValue(
        stringKeyedMapFromValue(decoded)['entries'],
      );
      final entry = entries[key];
      if (entry is! Map) return null;
      final expiresAt = webEngineNonNegativeIntFromValue(entry['expires_at']);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (expiresAt <= now) return null;
      final payloadRel = '${entry[payloadPathField] ?? ''}'.trim();
      if (payloadRel != webEngineCachePayloadFileName(key)) return null;
      final payloadFile = File(p.join(dir.path, payloadRel));
      if (!await webEngineEntityExists(payloadFile, deadline: deadline)) {
        return null;
      }
      final payload = await readWebEnginePayloadFile(
        payloadFile,
        deadline: deadline,
      );
      if (!_shuttingDown) {
        unawaited(_runSerialized('更新缓存访问时间', () => _touchAccess(key)));
      }
      return WebEngineCacheRawLookup(
        payload: payload,
        metadata: jsonSafeMap(Map.from(entry)),
        cachedAt: _dateTimeFromCacheMs(
          webEngineOptionalNonNegativeIntFromValue(entry['created_at']) ?? now,
          fallbackMs: now,
        ),
        expiresAt: _dateTimeFromCacheMs(expiresAt, fallbackMs: now),
      );
    } catch (error, stack) {
      silentLog(logTag, '查询缓存', error, stack);
      return null;
    } finally {
      deadline.stop();
    }
  }

  /// 写入一条新缓存：
  /// * 落 `<key>.txt`
  /// * 合并到 index.json：写入 created_at/expires_at/last_accessed_at + payload
  ///   字段（path/bytes/chars）+ [extraEntryFields]
  /// * 写完后按 `cacheMaxBytes` LRU 淘汰
  ///
  /// 只在 `isCacheEnabled` 且 [payload] 非空时生效。
  Future<void> baseStore({
    required String key,
    required TSettings settings,
    required String payload,
    required Map<String, Object?> extraEntryFields,
  }) async {
    if (_shuttingDown ||
        !isCacheEnabled(settings) ||
        !isValidWebEngineCacheKey(key)) {
      return;
    }
    if (nullIfBlank(payload) == null) return;
    await _runSerialized(
      '存储缓存',
      () => _writeEntry(
        key: key,
        settings: settings,
        payload: payload,
        extraEntryFields: extraEntryFields,
      ),
    );
  }

  Future<void> _runSerialized(
    String action,
    Future<void> Function() operation,
  ) => runWebEngineSerializedOperation(
    shuttingDown: _shuttingDown,
    queue: _operations,
    logTag: logTag,
    action: action,
    operation: operation,
  );

  Future<void> _writeEntry({
    required String key,
    required TSettings settings,
    required String payload,
    required Map<String, Object?> extraEntryFields,
  }) async {
    final dir = Directory(defaultDirectoryPath());
    await ensureWebEngineDirectory(dir);

    final payloadRel = webEngineCachePayloadFileName(key);
    if (payloadRel == null) return;
    final payloadFile = File(p.join(dir.path, payloadRel));
    final encoded = utf8.encode(payload);
    final configuredCap = cacheMaxBytes(settings);
    final safeCap = configuredCap > 0
        ? configuredCap
        : webEngineMaxPayloadFileBytes;
    final payloadLimit = safeCap.clamp(1, webEngineMaxPayloadFileBytes);
    if (encoded.length > payloadLimit) return;
    await writeFileAtomically(payloadFile, payload);

    final indexFile = File(p.join(dir.path, webEngineCacheIndexFileName));
    Map<String, Object?> root = <String, Object?>{};
    try {
      final decoded = await readWebEngineJsonFileIfExists(indexFile);
      if (decoded is Map) root = stringKeyedMapFromValue(decoded);
    } on FormatException {
      /* 索引损坏时按空索引处理。 */
    }
    final entries = webEngineCacheEntriesFromValue(root['entries']);
    if (!entries.containsKey(key) &&
        entries.length >= webEngineMaxIndexEntries) {
      final oldest = entries.entries.reduce((left, right) {
        return _cacheEntryLastAccessedAt(left.value) <=
                _cacheEntryLastAccessedAt(right.value)
            ? left
            : right;
      });
      entries.remove(oldest.key);
      final oldestValue = oldest.value;
      if (oldestValue is Map) {
        final oldestPayload = '${oldestValue[payloadPathField] ?? ''}'.trim();
        if (oldestPayload == webEngineCachePayloadFileName(oldest.key)) {
          final oldestFile = File(p.join(dir.path, oldestPayload));
          try {
            if (await webEngineEntityExists(oldestFile)) {
              await oldestFile.delete().timeout(webEngineFileOperationTimeout);
            }
          } catch (error, stack) {
            silentLog(logTag, '存储缓存并清理索引容量', error, stack);
          }
        }
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = now + cacheTtlSeconds(settings) * 1000;

    entries[key] = <String, Object?>{
      payloadPathField: payloadRel,
      payloadBytesField: encoded.length,
      payloadCharsField: payload.length,
      'created_at': now,
      'expires_at': expiresAt,
      'last_accessed_at': now,
      ...jsonSafeMap(extraEntryFields),
    };

    root['entries'] = entries;
    await writeWebEngineJsonFile(indexFile, jsonSafeMap(root));

    await _enforceCap(safeCap);
  }

  Future<void> _touchAccess(String key) async {
    final dir = Directory(defaultDirectoryPath());
    final indexFile = File(p.join(dir.path, webEngineCacheIndexFileName));
    try {
      final decoded = await readWebEngineJsonFileIfExists(indexFile);
      if (decoded is! Map) return;
      final root = stringKeyedMapFromValue(decoded);
      final entries = webEngineCacheEntriesFromValue(root['entries']);
      final entry = entries[key];
      if (entry is! Map) return;
      final updated = Map<String, Object?>.of(stringKeyedMapFromValue(entry));
      updated['last_accessed_at'] = DateTime.now().millisecondsSinceEpoch;
      entries[key] = updated;
      root['entries'] = entries;
      await writeWebEngineJsonFile(indexFile, jsonSafeMap(root));
    } catch (error, stack) {
      silentLog(logTag, '更新缓存访问时间', error, stack);
    }
  }

  Future<void> _enforceCap(int maxBytes) async {
    // 先按索引估算总量，仅在超限后读取真实磁盘大小并执行 LRU 淘汰。
    final dir = Directory(defaultDirectoryPath());
    final indexFile = File(p.join(dir.path, webEngineCacheIndexFileName));
    final deadline = WebEngineIoDeadline();
    late Map<String, Object?> root;
    late Map<String, Object?> entries;
    try {
      Object? decoded;
      try {
        decoded = await readWebEngineJsonFileIfExists(
          indexFile,
          deadline: deadline,
        );
      } on FormatException {
        return;
      }
      root = decoded is Map ? stringKeyedMapFromValue(decoded) : {};
      entries = webEngineCacheEntriesFromValue(root['entries']);

      var estimatedTotal = 0;
      for (final entry in entries.values) {
        if (entry is! Map) continue;
        estimatedTotal += webEngineNonNegativeIntFromValue(
          entry[payloadBytesField],
        );
      }
      estimatedTotal += utf8.encode(jsonEncode(jsonSafeMap(root))).length;
      if (estimatedTotal <= maxBytes) return;

      // 估算超阈值，再做真实磁盘读用于淘汰决策（孤儿文件 / index 字节字段缺失
      // 时仍需要兜底）。
      final usage = await measureWebEngineDirectoryBounded(
        dir,
        deadline: deadline,
      );
      if (usage.truncated) {
        silentLog(
          logTag,
          '执行容量限制并测量缓存',
          StateError('Web 引擎缓存空间统计已达到安全上限。'),
          StackTrace.current,
        );
        return;
      }
      final total = usage.totalBytes;
      if (total <= maxBytes) return;

      final ordered = entries.entries.toList()
        ..sort((a, b) {
          final av = a.value is Map
              ? webEngineNonNegativeIntFromValue(
                  (a.value as Map)['last_accessed_at'],
                )
              : 0;
          final bv = b.value is Map
              ? webEngineNonNegativeIntFromValue(
                  (b.value as Map)['last_accessed_at'],
                )
              : 0;
          return av.compareTo(bv);
        });

      var current = total;
      for (final entry in ordered) {
        if (current <= maxBytes) break;
        final value = entry.value;
        if (value is! Map) {
          entries.remove(entry.key);
          continue;
        }
        final payloadRel = '${value[payloadPathField] ?? ''}'.trim();
        if (payloadRel == webEngineCachePayloadFileName(entry.key)) {
          final f = File(p.join(dir.path, payloadRel));
          try {
            if (await webEngineEntityExists(f, deadline: deadline)) {
              current -= await f.length().timeout(
                deadline.nextOperationTimeout(),
              );
              await f.delete().timeout(deadline.nextOperationTimeout());
            }
          } on TimeoutException {
            break;
          } catch (error, stack) {
            silentLog(logTag, '执行容量限制并删除缓存', error, stack);
          }
        }
        entries.remove(entry.key);
      }
      root['entries'] = entries;
    } finally {
      deadline.stop();
    }

    try {
      await writeWebEngineJsonFile(indexFile, jsonSafeMap(root));
    } catch (error, stack) {
      silentLog(logTag, '执行容量限制并写入索引', error, stack);
    }
  }

  /// 停止接收新任务，并等待已入队写操作结束。
  Future<void> shutdown() {
    _shuttingDown = true;
    return _shutdownOnce.run(
      () => _operations.idle.timeout(runtimeCleanupTimeout),
    );
  }
}

int _cacheEntryLastAccessedAt(Object? value) {
  return value is Map
      ? webEngineNonNegativeIntFromValue(value['last_accessed_at'])
      : 0;
}

DateTime _dateTimeFromCacheMs(int value, {required int fallbackMs}) {
  try {
    return DateTime.fromMillisecondsSinceEpoch(value);
  } on RangeError {
    return DateTime.fromMillisecondsSinceEpoch(fallbackMs);
  }
}
