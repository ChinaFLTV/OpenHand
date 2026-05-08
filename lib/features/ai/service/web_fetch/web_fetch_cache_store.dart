import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../model/ai_web_fetch_settings.dart';

/// URL → 抓取内容元数据 + 内容文件的本地持久化缓存。
///
/// * 目录：`~/.openhand/cache/web_fetch/`（受全局「应用数据 → 数据清理 → 应用缓存」覆盖）
/// * 文件：`index.json` 维护元数据 + 总字节数；每条缓存内容单独写入 `<sha>.txt`
/// * 替换策略：写入超过 [AiWebFetchSettings.cacheMaxBytes] 时按 lastAccessedAt 淘汰最旧条目
/// * 过期策略：[AiWebFetchSettings.cacheTtlSeconds] 决定 expiresAt；read 时按需 prune
/// * 并发：所有写盘操作串联到 `_chain`，避免 index.json 互踩
class WebFetchCacheStore {
  WebFetchCacheStore._();

  static final WebFetchCacheStore instance = WebFetchCacheStore._();

  Future<void> _chain = Future.value();

  static String defaultDirectoryPath() =>
      p.join(OpenHandPaths.defaultCacheDirectoryPath(), 'web_fetch');

  /// 缓存键：URL + 用户 prompt（同一 URL 不同 prompt 视为独立缓存）。
  static String computeKey({required String url, required String prompt}) {
    final payload = jsonEncode(<String, Object?>{
      'url': url.trim(),
      'prompt': prompt.trim(),
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<WebFetchCacheLookup?> lookup({
    required String key,
    required AiWebFetchSettings settings,
  }) async {
    if (!settings.cacheEnabled) return null;
    final dir = Directory(defaultDirectoryPath());
    if (!await dir.exists()) return null;
    final indexFile = File(p.join(dir.path, 'index.json'));
    if (!await indexFile.exists()) return null;
    try {
      final raw = await indexFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final entries = (decoded['entries'] as Map?) ?? const {};
      final entry = entries[key];
      if (entry is! Map) return null;
      final expiresAt = (entry['expires_at'] as num?)?.toInt() ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (expiresAt <= now) return null;
      final contentRel = '${entry['content_path'] ?? ''}'.trim();
      if (contentRel.isEmpty) return null;
      final contentFile = File(p.join(dir.path, contentRel));
      if (!await contentFile.exists()) return null;
      final content = await contentFile.readAsString();
      _chain = _chain.then((_) => _touchAccess(key)).catchError((_) {});
      return WebFetchCacheLookup(
        content: content,
        metadata: Map<String, Object?>.from(entry),
        cachedAt: DateTime.fromMillisecondsSinceEpoch(
          (entry['created_at'] as num?)?.toInt() ?? now,
        ),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
      );
    } catch (error, stack) {
      silentLog('web_fetch_cache', 'lookup', error, stack);
      return null;
    }
  }

  Future<void> store({
    required String key,
    required AiWebFetchSettings settings,
    required String url,
    required String content,
    required Map<String, Object?> metadata,
  }) async {
    if (!settings.cacheEnabled) return;
    if (content.trim().isEmpty) return;
    _chain = _chain
        .then(
          (_) => _writeEntry(
            key: key,
            settings: settings,
            url: url,
            content: content,
            metadata: metadata,
          ),
        )
        .catchError((Object error, StackTrace stack) {
          silentLog('web_fetch_cache', 'store', error, stack);
        });
    await _chain;
  }

  Future<void> clearAll() async {
    _chain = _chain.then((_) async {
      final dir = Directory(defaultDirectoryPath());
      if (!await dir.exists()) return;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          await entity.delete(recursive: true);
        }
      } catch (error, stack) {
        silentLog('web_fetch_cache', 'clearAll', error, stack);
      }
    });
    await _chain;
  }

  Future<int> totalBytesOnDisk() async {
    final dir = Directory(defaultDirectoryPath());
    if (!await dir.exists()) return 0;
    var total = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {/* ignore */}
        }
      }
    } catch (error, stack) {
      silentLog('web_fetch_cache', 'totalBytesOnDisk', error, stack);
    }
    return total;
  }

  Future<WebFetchCachePrewarmReport> prewarm() async {
    var removedExpired = 0;
    var removedOrphanFiles = 0;
    var removedOrphanEntries = 0;
    final completer = Completer<WebFetchCachePrewarmReport>();
    _chain = _chain
        .then((_) async {
          final dir = Directory(defaultDirectoryPath());
          if (!await dir.exists()) {
            completer.complete(
              const WebFetchCachePrewarmReport(
                removedExpired: 0,
                removedOrphanFiles: 0,
                removedOrphanEntries: 0,
              ),
            );
            return;
          }
          final indexFile = File(p.join(dir.path, 'index.json'));
          Map<String, Object?> root = <String, Object?>{};
          if (await indexFile.exists()) {
            try {
              final raw = await indexFile.readAsString();
              final decoded = jsonDecode(raw);
              if (decoded is Map) root = Map<String, Object?>.from(decoded);
            } catch (_) {/* ignore */}
          }
          final entries = root['entries'] is Map
              ? Map<String, Object?>.from(root['entries'] as Map)
              : <String, Object?>{};
          final now = DateTime.now().millisecondsSinceEpoch;
          final keysToRemove = <String>[];
          final keepFileNames = <String>{'index.json'};
          for (final entry in entries.entries) {
            final value = entry.value;
            if (value is! Map) {
              keysToRemove.add(entry.key);
              continue;
            }
            final expiresAt = (value['expires_at'] as num?)?.toInt() ?? 0;
            final contentRel = '${value['content_path'] ?? ''}'.trim();
            if (expiresAt <= now) {
              keysToRemove.add(entry.key);
              if (contentRel.isNotEmpty) {
                final f = File(p.join(dir.path, contentRel));
                if (await f.exists()) {
                  try {
                    await f.delete();
                  } catch (_) {/* tolerate */}
                }
              }
              removedExpired++;
            } else if (contentRel.isEmpty) {
              keysToRemove.add(entry.key);
              removedOrphanEntries++;
            } else {
              final f = File(p.join(dir.path, contentRel));
              if (!await f.exists()) {
                keysToRemove.add(entry.key);
                removedOrphanEntries++;
              } else {
                keepFileNames.add(contentRel);
              }
            }
          }
          for (final k in keysToRemove) {
            entries.remove(k);
          }
          try {
            await for (final entity in dir.list(followLinks: false)) {
              if (entity is! File) continue;
              final name = p.basename(entity.path);
              if (keepFileNames.contains(name)) continue;
              if (!name.endsWith('.txt')) continue;
              try {
                await entity.delete();
                removedOrphanFiles++;
              } catch (_) {/* tolerate */}
            }
          } catch (_) {/* tolerate */}
          root['entries'] = entries;
          try {
            await indexFile.writeAsString(jsonEncode(root), flush: true);
          } catch (error, stack) {
            silentLog(
              'web_fetch_cache',
              'prewarm/writeIndex',
              error,
              stack,
            );
          }
          completer.complete(
            WebFetchCachePrewarmReport(
              removedExpired: removedExpired,
              removedOrphanFiles: removedOrphanFiles,
              removedOrphanEntries: removedOrphanEntries,
            ),
          );
        })
        .catchError((Object error, StackTrace stack) {
          silentLog('web_fetch_cache', 'prewarm', error, stack);
          if (!completer.isCompleted) {
            completer.complete(
              const WebFetchCachePrewarmReport(
                removedExpired: 0,
                removedOrphanFiles: 0,
                removedOrphanEntries: 0,
              ),
            );
          }
        });
    return completer.future;
  }

  Future<void> _writeEntry({
    required String key,
    required AiWebFetchSettings settings,
    required String url,
    required String content,
    required Map<String, Object?> metadata,
  }) async {
    final dir = Directory(defaultDirectoryPath());
    if (!await dir.exists()) await dir.create(recursive: true);

    final contentRel = '$key.txt';
    final contentFile = File(p.join(dir.path, contentRel));
    final encoded = utf8.encode(content);
    await contentFile.writeAsBytes(encoded, flush: true);

    final indexFile = File(p.join(dir.path, 'index.json'));
    Map<String, Object?> root = <String, Object?>{};
    if (await indexFile.exists()) {
      try {
        final raw = await indexFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map) root = Map<String, Object?>.from(decoded);
      } catch (_) {/* keep empty root */}
    }
    final entries = root['entries'] is Map
        ? Map<String, Object?>.from(root['entries'] as Map)
        : <String, Object?>{};

    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = now + settings.cacheTtlSeconds * 1000;

    entries[key] = <String, Object?>{
      'url': url,
      'content_path': contentRel,
      'content_bytes': encoded.length,
      'content_chars': content.length,
      'created_at': now,
      'expires_at': expiresAt,
      'last_accessed_at': now,
      ...metadata,
    };

    root['entries'] = entries;
    await indexFile.writeAsString(jsonEncode(root), flush: true);

    if (settings.cacheMaxBytes > 0) {
      await _enforceCap(settings.cacheMaxBytes);
    }
  }

  Future<void> _touchAccess(String key) async {
    final dir = Directory(defaultDirectoryPath());
    final indexFile = File(p.join(dir.path, 'index.json'));
    if (!await indexFile.exists()) return;
    try {
      final raw = await indexFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final root = Map<String, Object?>.from(decoded);
      final entries = root['entries'] is Map
          ? Map<String, Object?>.from(root['entries'] as Map)
          : <String, Object?>{};
      final entry = entries[key];
      if (entry is! Map) return;
      final updated = Map<String, Object?>.from(entry);
      updated['last_accessed_at'] = DateTime.now().millisecondsSinceEpoch;
      entries[key] = updated;
      root['entries'] = entries;
      await indexFile.writeAsString(jsonEncode(root), flush: true);
    } catch (error, stack) {
      silentLog('web_fetch_cache', 'touchAccess', error, stack);
    }
  }

  Future<void> _enforceCap(int maxBytes) async {
    final total = await totalBytesOnDisk();
    if (total <= maxBytes) return;

    final dir = Directory(defaultDirectoryPath());
    final indexFile = File(p.join(dir.path, 'index.json'));
    if (!await indexFile.exists()) return;
    Map<String, Object?> root;
    try {
      final raw = await indexFile.readAsString();
      final decoded = jsonDecode(raw);
      root = decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } catch (_) {
      return;
    }
    final entries = root['entries'] is Map
        ? Map<String, Object?>.from(root['entries'] as Map)
        : <String, Object?>{};

    final ordered = entries.entries.toList()
      ..sort((a, b) {
        final av =
            (a.value is Map ? (a.value as Map)['last_accessed_at'] : 0) as num? ??
                0;
        final bv =
            (b.value is Map ? (b.value as Map)['last_accessed_at'] : 0) as num? ??
                0;
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
      final contentRel = '${value['content_path'] ?? ''}'.trim();
      if (contentRel.isNotEmpty) {
        final f = File(p.join(dir.path, contentRel));
        if (await f.exists()) {
          try {
            current -= await f.length();
            await f.delete();
          } catch (error, stack) {
            silentLog(
              'web_fetch_cache',
              'enforceCap/delete',
              error,
              stack,
            );
          }
        }
      }
      entries.remove(entry.key);
    }

    root['entries'] = entries;
    try {
      await indexFile.writeAsString(jsonEncode(root), flush: true);
    } catch (error, stack) {
      silentLog('web_fetch_cache', 'enforceCap/writeIndex', error, stack);
    }
  }
}

class WebFetchCacheLookup {
  const WebFetchCacheLookup({
    required this.content,
    required this.metadata,
    required this.cachedAt,
    required this.expiresAt,
  });

  final String content;
  final Map<String, Object?> metadata;
  final DateTime cachedAt;
  final DateTime expiresAt;
}

class WebFetchCachePrewarmReport {
  const WebFetchCachePrewarmReport({
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
