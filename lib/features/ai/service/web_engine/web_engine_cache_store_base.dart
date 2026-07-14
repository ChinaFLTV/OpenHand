import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/input_value_parsing.dart';
import 'web_engine_persistence_io.dart';
import 'web_engine_value_parsing.dart';

/// WebSearch / WebFetch 共用的「prewarm/cleanup 报告」数据。
///
/// 两个领域字段完全一致，统一成同一个类，以 typedef 暴露给各自包内使用，
/// 公开 API 兼容旧名称。
class WebEngineCachePrewarmReport {
  const WebEngineCachePrewarmReport({
    required this.removedExpired,
    required this.removedOrphanFiles,
    required this.removedOrphanEntries,
  });

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
/// * 单实例 → 串行写盘 `_chain`，避免 index.json 互踩
/// * 目录 = `<openhand_cache>/<subdir>`，由子类指定 [subdir]
/// * 单条 entry 写在 `<key>.txt`，metadata 写在 `index.json` 的 `entries[key]` 中
/// * 子类只需声明：
///   * 三个 entry 字段名（`*_path/*_bytes/*_chars`）
///   * 取出 `cacheEnabled / cacheTtlSeconds / cacheMaxBytes` 的 `TSettings` 适配
///   * `logTag`（用于 silentLog 上下文）
abstract class WebEngineCacheStoreBase<TSettings> {
  WebEngineCacheStoreBase();

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

  /// 串行写盘队列：所有写 index.json / payload 的动作都接到这里。
  ///
  /// 子类可以读、迫于实现需要表面上是 public，但 *仅*限与本包内部实现使用。
  Future<void> chain = Future.value();

  /// 默认缓存目录路径。
  String defaultDirectoryPath() =>
      p.join(OpenHandPaths.defaultCacheDirectoryPath(), subdir);

  /// 计算当前缓存目录的总字节数（含 index）。
  Future<int> totalBytesOnDisk() async {
    final dir = Directory(defaultDirectoryPath());
    if (!await dir.exists()) return 0;
    try {
      final usage = await measureWebEngineDirectoryBounded(dir);
      if (usage.truncated) {
        silentLog(
          logTag,
          'totalBytesOnDisk',
          StateError('Web engine cache measurement reached its safety limit.'),
          StackTrace.current,
        );
      }
      return usage.totalBytes;
    } catch (error, stack) {
      silentLog(logTag, 'totalBytesOnDisk', error, stack);
      return 0;
    }
  }

  /// 用于全局「应用数据 → 数据清理」直接调用：清空整个目录。
  Future<void> clearAll() async {
    chain = chain.then((_) async {
      final dir = Directory(defaultDirectoryPath());
      if (!await dir.exists()) return;
      try {
        final complete = await clearWebEngineDirectoryBounded(dir);
        if (!complete) {
          throw StateError(
            'Web engine cache cleanup reached its safety limit.',
          );
        }
      } catch (error, stack) {
        silentLog(logTag, 'clearAll', error, stack);
      }
    });
    await chain;
  }

  /// 应用启动后的「缓存预热 / 自愈」：扫描磁盘并重建 index.json。
  ///
  /// * 删除已过期条目（含其 .txt 文件）。
  /// * 删除磁盘上 .txt 文件已丢失的孤儿条目。
  /// * 删除 index 未登记的孤儿 .txt 文件。
  Future<WebEngineCachePrewarmReport> prewarm() async {
    var removedExpired = 0;
    var removedOrphanFiles = 0;
    var removedOrphanEntries = 0;
    final completer = Completer<WebEngineCachePrewarmReport>();
    chain = chain
        .then((_) async {
          final deadline = WebEngineIoDeadline();
          try {
            final dir = Directory(defaultDirectoryPath());
            if (!await dir.exists().timeout(deadline.nextOperationTimeout())) {
              completer.complete(
                const WebEngineCachePrewarmReport(
                  removedExpired: 0,
                  removedOrphanFiles: 0,
                  removedOrphanEntries: 0,
                ),
              );
              return;
            }
            final indexFile = File(p.join(dir.path, 'index.json'));
            Map<String, Object?> root = <String, Object?>{};
            if (await indexFile.exists().timeout(
              deadline.nextOperationTimeout(),
            )) {
              try {
                final decoded = await readWebEngineJsonFile(indexFile);
                if (decoded is Map) root = stringKeyedMapFromValue(decoded);
              } catch (_) {
                /* corrupt index: 视作空 */
              }
            }
            final entries = webEngineCacheEntriesFromValue(root['entries']);

            final now = DateTime.now().millisecondsSinceEpoch;
            final keysToRemove = <String>[];
            final keepFileNames = <String>{'index.json'};
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
                if (await f.exists().timeout(deadline.nextOperationTimeout())) {
                  try {
                    await f.delete().timeout(deadline.nextOperationTimeout());
                  } catch (_) {
                    /* tolerate */
                  }
                }
                removedExpired++;
              } else {
                final f = File(p.join(dir.path, payloadRel));
                if (!await f.exists().timeout(
                  deadline.nextOperationTimeout(),
                )) {
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
              final listing = await listWebEngineDirectoryBounded(
                dir,
                deadline,
              );
              for (final entity in listing.entries) {
                if (entity is! File) continue;
                final name = p.basename(entity.path);
                if (keepFileNames.contains(name)) continue;
                if (!name.endsWith('.txt')) continue;
                try {
                  await entity.delete().timeout(
                    deadline.nextOperationTimeout(),
                  );
                  removedOrphanFiles++;
                } catch (_) {
                  /* tolerate */
                }
              }
            } catch (_) {
              /* tolerate listing failure */
            }

            root['entries'] = entries;
            try {
              await writeWebEngineJsonFile(indexFile, _jsonSafeCacheMap(root));
            } catch (error, stack) {
              silentLog(logTag, 'prewarm/writeIndex', error, stack);
            }
            completer.complete(
              WebEngineCachePrewarmReport(
                removedExpired: removedExpired,
                removedOrphanFiles: removedOrphanFiles,
                removedOrphanEntries: removedOrphanEntries,
              ),
            );
          } finally {
            deadline.stop();
          }
        })
        .catchError((Object error, StackTrace stack) {
          silentLog(logTag, 'prewarm', error, stack);
          if (!completer.isCompleted) {
            completer.complete(
              const WebEngineCachePrewarmReport(
                removedExpired: 0,
                removedOrphanFiles: 0,
                removedOrphanEntries: 0,
              ),
            );
          }
        });
    return completer.future;
  }

  // protected helpers (子类的 typed lookup/store 调用)
  /// 命中查询：未启用 / 不存在 / 过期 / payload 文件丢失 → 全部返回 null。
  /// 命中后异步触发 `_touchAccess` 更新 last_accessed_at。
  Future<WebEngineCacheRawLookup?> baseLookup({
    required String key,
    required TSettings settings,
  }) async {
    if (!isCacheEnabled(settings) || !isValidWebEngineCacheKey(key)) {
      return null;
    }
    final dir = Directory(defaultDirectoryPath());
    if (!await dir.exists()) return null;
    final indexFile = File(p.join(dir.path, 'index.json'));
    if (!await indexFile.exists()) return null;
    try {
      final decoded = await readWebEngineJsonFile(indexFile);
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
      if (!await payloadFile.exists()) return null;
      final payload = await readWebEnginePayloadFile(payloadFile);
      chain = chain.then((_) => _touchAccess(key)).catchError((_) {});
      return WebEngineCacheRawLookup(
        payload: payload,
        metadata: _jsonSafeCacheMap(Map.from(entry)),
        cachedAt: _dateTimeFromCacheMs(
          webEngineOptionalNonNegativeIntFromValue(entry['created_at']) ?? now,
          fallbackMs: now,
        ),
        expiresAt: _dateTimeFromCacheMs(expiresAt, fallbackMs: now),
      );
    } catch (error, stack) {
      silentLog(logTag, 'lookup', error, stack);
      return null;
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
    if (!isCacheEnabled(settings) || !isValidWebEngineCacheKey(key)) return;
    if (nullIfBlank(payload) == null) return;
    chain = chain
        .then(
          (_) => _writeEntry(
            key: key,
            settings: settings,
            payload: payload,
            extraEntryFields: extraEntryFields,
          ),
        )
        .catchError((Object error, StackTrace stack) {
          silentLog(logTag, 'store', error, stack);
        });
    await chain;
  }

  Future<void> _writeEntry({
    required String key,
    required TSettings settings,
    required String payload,
    required Map<String, Object?> extraEntryFields,
  }) async {
    final dir = Directory(defaultDirectoryPath());
    if (!await dir.exists()) await dir.create(recursive: true);

    final payloadRel = webEngineCachePayloadFileName(key);
    if (payloadRel == null) return;
    final payloadFile = File(p.join(dir.path, payloadRel));
    final encoded = utf8.encode(payload);
    final configuredCap = cacheMaxBytes(settings);
    final payloadLimit = configuredCap > 0
        ? configuredCap.clamp(1, webEngineMaxPayloadFileBytes)
        : webEngineMaxPayloadFileBytes;
    if (encoded.length > payloadLimit) return;
    await writeFileAtomically(payloadFile, payload);

    final indexFile = File(p.join(dir.path, 'index.json'));
    Map<String, Object?> root = <String, Object?>{};
    if (await indexFile.exists()) {
      try {
        final decoded = await readWebEngineJsonFile(indexFile);
        if (decoded is Map) root = stringKeyedMapFromValue(decoded);
      } catch (_) {
        /* keep empty root */
      }
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
            if (await oldestFile.exists().timeout(
              webEngineFileOperationTimeout,
            )) {
              await oldestFile.delete().timeout(webEngineFileOperationTimeout);
            }
          } catch (error, stack) {
            silentLog(logTag, 'store/evictIndexCapacity', error, stack);
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
      ..._jsonSafeCacheMap(extraEntryFields),
    };

    root['entries'] = entries;
    await writeWebEngineJsonFile(indexFile, _jsonSafeCacheMap(root));

    final cap = cacheMaxBytes(settings);
    if (cap > 0) {
      await _enforceCap(cap);
    }
  }

  Future<void> _touchAccess(String key) async {
    final dir = Directory(defaultDirectoryPath());
    final indexFile = File(p.join(dir.path, 'index.json'));
    if (!await indexFile.exists()) return;
    try {
      final decoded = await readWebEngineJsonFile(indexFile);
      if (decoded is! Map) return;
      final root = stringKeyedMapFromValue(decoded);
      final entries = webEngineCacheEntriesFromValue(root['entries']);
      final entry = entries[key];
      if (entry is! Map) return;
      final updated = Map<String, Object?>.of(stringKeyedMapFromValue(entry));
      updated['last_accessed_at'] = DateTime.now().millisecondsSinceEpoch;
      entries[key] = updated;
      root['entries'] = entries;
      await writeWebEngineJsonFile(indexFile, _jsonSafeCacheMap(root));
    } catch (error, stack) {
      silentLog(logTag, 'touchAccess', error, stack);
    }
  }

  Future<void> _enforceCap(int maxBytes) async {
    // 旧实现每次写入都会调用 [totalBytesOnDisk]，递归 list 整个目录并对每个
    // 文件做 .length()——是热路径上的 O(N) IO。改为先从 index.json 估算总量
    // （我们在写入时已经把 payloadBytesField 落库），仅在估算超过阈值后再去
    // 走真实磁盘大小做精确判断 + LRU 淘汰。
    final dir = Directory(defaultDirectoryPath());
    final indexFile = File(p.join(dir.path, 'index.json'));
    if (!await indexFile.exists()) return;
    Map<String, Object?> root;
    try {
      final decoded = await readWebEngineJsonFile(indexFile);
      root = decoded is Map ? stringKeyedMapFromValue(decoded) : {};
    } catch (_) {
      return;
    }
    final entries = webEngineCacheEntriesFromValue(root['entries']);

    var estimatedTotal = 0;
    for (final entry in entries.values) {
      if (entry is! Map) continue;
      estimatedTotal += webEngineNonNegativeIntFromValue(
        entry[payloadBytesField],
      );
    }
    estimatedTotal += utf8.encode(jsonEncode(_jsonSafeCacheMap(root))).length;
    if (estimatedTotal <= maxBytes) return;

    // 估算超阈值，再做真实磁盘读用于淘汰决策（孤儿文件 / index 字节字段缺失
    // 时仍需要兜底）。
    final usage = await measureWebEngineDirectoryBounded(dir);
    if (usage.truncated) {
      silentLog(
        logTag,
        'enforceCap/measure',
        StateError('Web engine cache measurement reached its safety limit.'),
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
    final deadline = WebEngineIoDeadline();
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
          if (await f.exists().timeout(deadline.nextOperationTimeout())) {
            current -= await f.length().timeout(
              deadline.nextOperationTimeout(),
            );
            await f.delete().timeout(deadline.nextOperationTimeout());
          }
        } on TimeoutException {
          break;
        } catch (error, stack) {
          silentLog(logTag, 'enforceCap/delete', error, stack);
        }
      }
      entries.remove(entry.key);
    }
    deadline.stop();

    root['entries'] = entries;
    try {
      await writeWebEngineJsonFile(indexFile, _jsonSafeCacheMap(root));
    } catch (error, stack) {
      silentLog(logTag, 'enforceCap/writeIndex', error, stack);
    }
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

Map<String, Object?> _jsonSafeCacheMap(Map<Object?, Object?> value) {
  return <String, Object?>{
    for (final entry in value.entries)
      '${entry.key}': _jsonSafeCacheValue(entry.value),
  };
}

Object? _jsonSafeCacheValue(Object? value) {
  if (value is num && !value.isFinite) return 0;
  if (value is Map) return _jsonSafeCacheMap(value);
  if (value is List) {
    return value.map(_jsonSafeCacheValue).toList(growable: false);
  }
  return value;
}
