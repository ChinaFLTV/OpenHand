/// 网络多媒体本地缓存服务。
///
/// 当 AI 生成的图片/视频/音频首次下载失败后, 消息内容中保留的是原始网络 URL。
/// 每次渲染时 Flutter 的 `Image.network` 都需要重新从网络拉取, 体验极差。
///
/// 本服务在网络多媒体成功加载后, 后台将其缓存到 `openhand_media` 目录,
/// 下次渲染时直接走本地文件, 实现"重试缓存"的性能优化。
///
/// 设计要点:
/// - 单例模式, 全局共享下载队列, 避免同一 URL 重复下载。
/// - fire-and-forget: 调用方不等待结果, 不阻塞 UI。
/// - 缓存目录与 `saveInlineMediaToMarkdown` 共用 `openhand_media`,
///   数据清理模块统一管理。
/// - 文件名基于 URL 的 SHA-256 前 16 字节 hex + 原始扩展名, 保证唯一且可逆查找。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';

/// 网络多媒体本地缓存管理器 (单例)。
class MediaCacheService {
  MediaCacheService._();
  static final MediaCacheService instance = MediaCacheService._();

  /// 正在下载中的 URL 集合, 防止同一 URL 并发下载。
  final Set<String> _inflight = <String>{};

  /// 缓存目录 (懒初始化)。与 `ai_protocol_adapter.dart` 中的
  /// `_ensureInlineMediaDir()` 保持一致。
  Directory? _cacheDir;

  /// 获取缓存目录路径 (不创建)。供数据清理模块使用。
  static String get cacheDirectoryPath =>
      p.join(Directory.systemTemp.path, 'openhand_media');

  Future<Directory> _ensureCacheDir() async {
    final existing = _cacheDir;
    if (existing != null && existing.existsSync()) return existing;
    final dir = Directory(cacheDirectoryPath);
    await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  /// 根据网络 URL 生成本地缓存文件路径。不检查文件是否存在。
  String _cacheFilePathForUrl(String url, String dir) {
    final hash = sha256.convert(utf8.encode(url)).toString().substring(0, 32);
    final ext = _extensionFromUrl(url);
    return p.join(dir, 'cached_$hash$ext');
  }

  /// 同步检查某个网络 URL 是否已有本地缓存。
  /// 返回本地文件路径 (存在时) 或 null。
  String? cachedPathForUrl(String url) {
    if (url.isEmpty) return null;
    final dir = cacheDirectoryPath;
    final path = _cacheFilePathForUrl(url, dir);
    if (File(path).existsSync()) return path;
    return null;
  }

  /// 触发后台缓存: 如果 URL 尚未缓存且未在下载中, 启动异步下载。
  /// 调用方无需 await, 纯 fire-and-forget。
  void cacheInBackground(String url) {
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;
    // 已缓存则跳过。
    if (cachedPathForUrl(url) != null) return;
    // 已在下载中则跳过。
    if (_inflight.contains(url)) return;
    _inflight.add(url);
    _downloadAndCache(url).whenComplete(() => _inflight.remove(url));
  }

  Future<void> _downloadAndCache(String url) async {
    try {
      final dir = await _ensureCacheDir();
      final destPath = _cacheFilePathForUrl(url, dir.path);
      final tempPath = '$destPath.tmp';
      final uri = Uri.parse(url);

      final client = SystemProxyResolver.instance.createRawHttpClient();
      try {
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 15));
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>();
          return;
        }
        // 验证 content-type: 只缓存图片/视频/音频。
        final contentType = response.headers.contentType;
        if (contentType != null) {
          final primary = contentType.primaryType;
          if (primary != 'image' && primary != 'video' && primary != 'audio') {
            await response.drain<void>();
            return;
          }
        }
        // 限制单文件最大 50MB, 防止恶意/异常响应撑爆磁盘。
        const maxBytes = 50 * 1024 * 1024;
        final tempFile = File(tempPath);
        final sink = tempFile.openWrite();
        int written = 0;
        bool aborted = false;
        try {
          await for (final chunk in response.timeout(
            const Duration(seconds: 30),
          )) {
            written += chunk.length;
            if (written > maxBytes) {
              aborted = true;
              break;
            }
            sink.add(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (aborted) {
          // 超限: 删除临时文件, 不缓存。
          try { await tempFile.delete(); } catch (_) {}
          return;
        }
        // 原子重命名: 避免读到半写文件。
        await tempFile.rename(destPath);
      } finally {
        client.close(force: true);
      }
    } catch (e, st) {
      silentLog('media_cache', 'download', e, st);
      // 清理可能残留的临时文件。
      try {
        final dir = await _ensureCacheDir();
        final tempPath = '${_cacheFilePathForUrl(url, dir.path)}.tmp';
        final tempFile = File(tempPath);
        if (tempFile.existsSync()) await tempFile.delete();
      } catch (_) {}
    }
  }

  /// 从 URL 中提取文件扩展名。
  static String _extensionFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegment = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : '';
      final ext = p.extension(pathSegment).toLowerCase();
      if (ext.isNotEmpty && ext.length <= 6) return ext;
    } catch (_) {}
    return '.bin';
  }

  /// 测算缓存目录总体积 (供数据清理模块使用)。
  static Future<int> totalCacheBytes() async {
    final dir = Directory(cacheDirectoryPath);
    if (!dir.existsSync()) return 0;
    int total = 0;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// 清空缓存目录内容 (供数据清理模块使用)。
  static Future<void> clearCache() async {
    final dir = Directory(cacheDirectoryPath);
    if (!dir.existsSync()) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }
}
