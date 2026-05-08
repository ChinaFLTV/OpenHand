import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../model/ai_web_search_settings.dart';

/// 关键词 → summary 元数据的本地持久化缓存。
///
/// * 目录：`~/.openhand/cache/web_search/`（受全局「应用数据 → 数据清理 → 应用缓存」覆盖）
/// * 文件：`index.json` 维护元数据 + 总字节数；每条缓存 summary 单独写入 `<sha>.txt`
/// * 替换策略：写入超过 [AiWebSearchSettings.cacheMaxBytes] 时按 lastAccessedAt 淘汰最旧条目
/// * 过期策略：[AiWebSearchSettings.cacheTtlSeconds] 决定 expiresAt；read 时按需 prune
/// * 并发：所有写盘操作串联到 `_chain`，避免 index.json 互踩
class WebSearchCacheStore {
  WebSearchCacheStore._();

  static final WebSearchCacheStore instance = WebSearchCacheStore._();

  Future<void> _chain = Future.value();

  /// 默认缓存目录路径。
  static String defaultDirectoryPath() =>
      p.join(OpenHandPaths.defaultCacheDirectoryPath(), 'web_search');

  /// 计算缓存键：covers query + 启用的引擎 + 结果数 + summary 风格/长度 + locale。
  /// 任何会显著影响 summary 内容的设置都参与摘要，避免脏读。
  static String computeKey({
    required String query,
    required AiWebSearchSettings settings,
    required List<String> allowedDomains,
    required List<String> blockedDomains,
    required String localeTag,
  }) {
    final enabled = settings.enabledEnginesInOrder()
        .map((e) => '${e.kind.name}:${e.weight}:${e.truncationChars}')
        .toList(growable: false)
      ..sort();
    final allow = [...allowedDomains]..sort();
    final block = [...blockedDomains]..sort();
    final payload = jsonEncode(<String, Object?>{
      'q': query.toLowerCase().trim(),
      'engines': enabled,
      'allow': allow,
      'block': block,
      'r': settings.resultCount,
      'd': settings.summaryDetail.name,
      's': settings.summaryStyle.name,
      'min': settings.summaryMinChars,
      'max': settings.summaryMaxChars,
      'mode': settings.modelMode.name,
      'fixed':
          '${settings.fixedModelProviderConfigId ?? ''}/${settings.fixedModelId ?? ''}',
      'locale': localeTag,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// 读取一条缓存。命中 + 未过期返回 [WebSearchCacheLookup]，否则 null。
  /// 命中后会更新 lastAccessedAt 并增量保存 index（异步、不阻塞调用方）。
  Future<WebSearchCacheLookup?> lookup({
    required String key,
    required AiWebSearchSettings settings,
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
      final summaryRel = '${entry['summary_path'] ?? ''}'.trim();
      if (summaryRel.isEmpty) return null;
      final summaryFile = File(p.join(dir.path, summaryRel));
      if (!await summaryFile.exists()) return null;
      final summary = await summaryFile.readAsString();
      // touch lastAccessedAt 异步进行
      _chain = _chain.then((_) => _touchAccess(key)).catchError((_) {});
      return WebSearchCacheLookup(
        summary: summary,
        metadata: Map<String, Object?>.from(entry),
        cachedAt: DateTime.fromMillisecondsSinceEpoch(
          (entry['created_at'] as num?)?.toInt() ?? now,
        ),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
      );
    } catch (error, stack) {
      silentLog('web_search_cache', 'lookup', error, stack);
      return null;
    }
  }

  /// 写入一条新的缓存。空 summary 直接忽略。
  Future<void> store({
    required String key,
    required AiWebSearchSettings settings,
    required String query,
    required String summary,
    required Map<String, Object?> metadata,
  }) async {
    if (!settings.cacheEnabled) return;
    if (summary.trim().isEmpty) return;
    _chain = _chain
        .then((_) => _writeEntry(
              key: key,
              settings: settings,
              query: query,
              summary: summary,
              metadata: metadata,
            ))
        .catchError((Object error, StackTrace stack) {
          silentLog('web_search_cache', 'store', error, stack);
        });
    await _chain;
  }

  /// 用于全局「应用数据 → 数据清理」直接调用：清空整个目录。
  Future<void> clearAll() async {
    _chain = _chain.then((_) async {
      final dir = Directory(defaultDirectoryPath());
      if (!await dir.exists()) return;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          await entity.delete(recursive: true);
        }
      } catch (error, stack) {
        silentLog('web_search_cache', 'clearAll', error, stack);
      }
    });
    await _chain;
  }

  /// 计算当前缓存目录的总字节数（含 index）。
  Future<int> totalBytesOnDisk() async {
    final dir = Directory(defaultDirectoryPath());
    if (!await dir.exists()) return 0;
    var total = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {/* ignore single file failure */}
        }
      }
    } catch (error, stack) {
      silentLog('web_search_cache', 'totalBytesOnDisk', error, stack);
    }
    return total;
  }

  /// 应用启动后的「缓存预热 / 自愈」：扫描磁盘并重建 index.json。
  ///
  /// * 删除已过期条目（含其 .txt 文件）。
  /// * 删除磁盘上 .txt 文件已丢失的孤儿条目。
  /// * 删除 index 未登记的孤儿 .txt 文件（人为残留 / 上一轮意外中断）。
  /// * 不在 index 中但磁盘有条目的情形使用默认 TTL=now 即丢弃；这里不做
  ///   反向重建以避免读取陌生 utf8 内容。
  ///
  /// 由 main.dart 在 boot 期间 fire-and-forget 调用，全部失败均 silent。
  Future<WebSearchCachePrewarmReport> prewarm() async {
    var removedExpired = 0;
    var removedOrphanFiles = 0;
    var removedOrphanEntries = 0;
    final completer = Completer<WebSearchCachePrewarmReport>();
    _chain = _chain.then((_) async {
      final dir = Directory(defaultDirectoryPath());
      if (!await dir.exists()) {
        completer.complete(const WebSearchCachePrewarmReport(
          removedExpired: 0,
          removedOrphanFiles: 0,
          removedOrphanEntries: 0,
        ));
        return;
      }
      final indexFile = File(p.join(dir.path, 'index.json'));
      Map<String, Object?> root = <String, Object?>{};
      if (await indexFile.exists()) {
        try {
          final raw = await indexFile.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is Map) root = Map<String, Object?>.from(decoded);
        } catch (_) {/* corrupt index: 视作空 */}
      }
      final entries = root['entries'] is Map
          ? Map<String, Object?>.from(root['entries'] as Map)
          : <String, Object?>{};

      final now = DateTime.now().millisecondsSinceEpoch;
      // 1) 扫描 entries：过期 + summary 文件丢失
      final keysToRemove = <String>[];
      final keepFileNames = <String>{'index.json'};
      for (final entry in entries.entries) {
        final value = entry.value;
        if (value is! Map) {
          keysToRemove.add(entry.key);
          continue;
        }
        final expiresAt = (value['expires_at'] as num?)?.toInt() ?? 0;
        final summaryRel = '${value['summary_path'] ?? ''}'.trim();
        if (expiresAt <= now) {
          keysToRemove.add(entry.key);
          if (summaryRel.isNotEmpty) {
            final f = File(p.join(dir.path, summaryRel));
            if (await f.exists()) {
              try {
                await f.delete();
              } catch (_) {/* tolerate */}
            }
          }
          removedExpired++;
        } else if (summaryRel.isEmpty) {
          keysToRemove.add(entry.key);
          removedOrphanEntries++;
        } else {
          final f = File(p.join(dir.path, summaryRel));
          if (!await f.exists()) {
            keysToRemove.add(entry.key);
            removedOrphanEntries++;
          } else {
            keepFileNames.add(summaryRel);
          }
        }
      }
      for (final k in keysToRemove) {
        entries.remove(k);
      }

      // 2) 扫描磁盘：把不在 keep 列表的 .txt 视为孤儿删除
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
      } catch (_) {/* tolerate listing failure */}

      // 3) 写回 index（即使 entries 为空也保留正确结构）
      root['entries'] = entries;
      try {
        await indexFile.writeAsString(jsonEncode(root), flush: true);
      } catch (error, stack) {
        silentLog('web_search_cache', 'prewarm/writeIndex', error, stack);
      }
      completer.complete(WebSearchCachePrewarmReport(
        removedExpired: removedExpired,
        removedOrphanFiles: removedOrphanFiles,
        removedOrphanEntries: removedOrphanEntries,
      ));
    }).catchError((Object error, StackTrace stack) {
      silentLog('web_search_cache', 'prewarm', error, stack);
      if (!completer.isCompleted) {
        completer.complete(const WebSearchCachePrewarmReport(
          removedExpired: 0,
          removedOrphanFiles: 0,
          removedOrphanEntries: 0,
        ));
      }
    });
    return completer.future;
  }

  // ---------------------------------------------------------------------------

  Future<void> _writeEntry({
    required String key,
    required AiWebSearchSettings settings,
    required String query,
    required String summary,
    required Map<String, Object?> metadata,
  }) async {
    final dir = Directory(defaultDirectoryPath());
    if (!await dir.exists()) await dir.create(recursive: true);

    // 写 summary 内容
    final summaryRel = '$key.txt';
    final summaryFile = File(p.join(dir.path, summaryRel));
    final encoded = utf8.encode(summary);
    await summaryFile.writeAsBytes(encoded, flush: true);

    // 加载/构造 index
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
      'query': query,
      'summary_path': summaryRel,
      'summary_bytes': encoded.length,
      'summary_chars': summary.length,
      'created_at': now,
      'expires_at': expiresAt,
      'last_accessed_at': now,
      ...metadata,
    };

    root['entries'] = entries;
    await indexFile.writeAsString(jsonEncode(root), flush: true);

    // 强制容量上限 → LRU 淘汰
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
      silentLog('web_search_cache', 'touchAccess', error, stack);
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

    // 按 last_accessed_at 升序（最旧在前）排序
    final ordered = entries.entries.toList()
      ..sort((a, b) {
        final av = (a.value is Map ? (a.value as Map)['last_accessed_at'] : 0)
                as num? ??
            0;
        final bv = (b.value is Map ? (b.value as Map)['last_accessed_at'] : 0)
                as num? ??
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
      final summaryRel = '${value['summary_path'] ?? ''}'.trim();
      if (summaryRel.isNotEmpty) {
        final f = File(p.join(dir.path, summaryRel));
        if (await f.exists()) {
          try {
            current -= await f.length();
            await f.delete();
          } catch (error, stack) {
            silentLog('web_search_cache', 'enforceCap/delete', error, stack);
          }
        }
      }
      entries.remove(entry.key);
    }

    root['entries'] = entries;
    try {
      await indexFile.writeAsString(jsonEncode(root), flush: true);
    } catch (error, stack) {
      silentLog('web_search_cache', 'enforceCap/writeIndex', error, stack);
    }
  }
}

class WebSearchCacheLookup {
  const WebSearchCacheLookup({
    required this.summary,
    required this.metadata,
    required this.cachedAt,
    required this.expiresAt,
  });

  final String summary;
  final Map<String, Object?> metadata;
  final DateTime cachedAt;
  final DateTime expiresAt;
}

/// [WebSearchCacheStore.prewarm] 返回的清理统计，纯诊断用途。
class WebSearchCachePrewarmReport {
  const WebSearchCachePrewarmReport({
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
