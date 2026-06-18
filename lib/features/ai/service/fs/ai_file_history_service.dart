import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';

/// 文件编辑历史版本服务
///
/// 核心机制：
/// 1. 每次 Edit/Write 前保存文件当前内容的快照
/// 2. 每个文件保留最近 N 个版本
/// 3. 支持回滚到指定版本
class AiFileHistoryService {
  AiFileHistoryService({String? historyDirectory, this.maxVersionsPerFile = 10})
    : _historyDirectory = historyDirectory;

  final String? _historyDirectory;
  final int maxVersionsPerFile;

  /// 获取历史版本存储目录
  ///
  /// 默认路径从 `Directory.systemTemp/.openhand-file-history`
  /// 切换到 `~/.openhand/file_history/legacy_versions/`，与其他 OpenHand
  /// 应用数据位置保持一致，供全局「数据清理」控制。
  Future<Directory> _getHistoryDir() async {
    final baseDir =
        _historyDirectory ??
        p.join(
          OpenHandPaths.defaultRootDirectoryPath(),
          'file_history',
          'legacy_versions',
        );
    final dir = Directory(baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 保存文件的历史版本（在编辑前调用）
  ///
  /// 返回版本 ID，用于可能的回滚
  Future<String?> saveVersion({
    required String filePath,
    required String sessionId,
    String? toolCallId,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    try {
      final historyDir = await _getHistoryDir();
      final normalizedPath = p.normalize(filePath);

      // 生成文件哈希作为子目录名（避免路径冲突）
      final pathHash = _hashPath(normalizedPath);
      final fileHistoryDir = Directory(p.join(historyDir.path, pathHash));
      if (!await fileHistoryDir.exists()) {
        await fileHistoryDir.create(recursive: true);
      }

      // 版本 ID = 时间戳 + UUID 后缀
      final timestamp = DateTime.now().toUtc();
      final versionId =
          '${timestamp.millisecondsSinceEpoch}_${toolCallId ?? 'manual'}';

      // 读取当前内容
      final content = await file.readAsString();

      // 保存版本元数据
      final versionMetadata = <String, Object?>{
        'version_id': versionId,
        'file_path': normalizedPath,
        'session_id': sessionId,
        'tool_call_id': toolCallId,
        'created_at': timestamp.toIso8601String(),
        'file_size_bytes': content.length,
      };

      // 保存内容文件
      final contentFile = File(
        p.join(fileHistoryDir.path, '$versionId.content'),
      );
      await writeFileAtomically(contentFile, content);

      // 保存元数据文件
      final metadataFile = File(
        p.join(fileHistoryDir.path, '$versionId.meta.json'),
      );
      await writeFileAtomically(metadataFile, jsonEncode(versionMetadata));

      // 清理旧版本
      await _pruneOldVersions(fileHistoryDir);

      return versionId;
    } catch (e) {
      // 历史版本保存失败不应阻断编辑操作
      return null;
    }
  }

  /// 获取文件的版本历史列表
  Future<List<FileVersionInfo>> getVersionHistory(String filePath) async {
    try {
      final historyDir = await _getHistoryDir();
      final normalizedPath = p.normalize(filePath);
      final pathHash = _hashPath(normalizedPath);
      final fileHistoryDir = Directory(p.join(historyDir.path, pathHash));

      if (!await fileHistoryDir.exists()) {
        return const <FileVersionInfo>[];
      }

      final versions = <FileVersionInfo>[];
      await for (final entity in fileHistoryDir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.meta.json')) {
          try {
            final metaContent = await entity.readAsString();
            final meta = jsonDecode(metaContent) as Map<String, Object?>;
            versions.add(FileVersionInfo.fromJson(meta));
          } catch (_) {
            // 跳过损坏的元数据文件
          }
        }
      }

      // 按时间倒序排列
      versions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return versions;
    } catch (e) {
      return const <FileVersionInfo>[];
    }
  }

  /// 回滚到指定版本
  Future<RollbackResult> rollbackToVersion({
    required String filePath,
    required String versionId,
  }) async {
    try {
      final historyDir = await _getHistoryDir();
      final normalizedPath = p.normalize(filePath);
      final pathHash = _hashPath(normalizedPath);
      final fileHistoryDir = Directory(p.join(historyDir.path, pathHash));

      final contentFile = File(
        p.join(fileHistoryDir.path, '$versionId.content'),
      );
      if (!await contentFile.exists()) {
        return const RollbackResult.failure('Version not found');
      }

      // 先保存当前版本（作为回滚前的备份）
      await saveVersion(
        filePath: filePath,
        sessionId: 'rollback-backup',
        toolCallId: 'pre-rollback-${DateTime.now().millisecondsSinceEpoch}',
      );

      // 恢复历史版本
      final historicContent = await contentFile.readAsString();
      final targetFile = File(normalizedPath);
      await targetFile.writeAsString(historicContent);

      return RollbackResult.success(versionId);
    } catch (e) {
      return RollbackResult.failure('Rollback failed: $e');
    }
  }

  /// 清理超出限制的旧版本
  Future<void> _pruneOldVersions(Directory fileHistoryDir) async {
    try {
      final metaFiles = <File>[];
      await for (final entity in fileHistoryDir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.meta.json')) {
          metaFiles.add(entity);
        }
      }

      if (metaFiles.length <= maxVersionsPerFile) return;

      // 按修改时间排序
      final fileStats = <File, DateTime>{};
      for (final file in metaFiles) {
        final stat = await file.stat();
        fileStats[file] = stat.modified;
      }
      metaFiles.sort((a, b) => fileStats[b]!.compareTo(fileStats[a]!));

      // 删除超出限制的旧版本
      for (var i = maxVersionsPerFile; i < metaFiles.length; i++) {
        final metaFile = metaFiles[i];
        final versionId = p.basenameWithoutExtension(
          metaFile.path.replaceAll('.meta.json', ''),
        );
        await metaFile.delete();
        final contentFile = File(
          p.join(fileHistoryDir.path, '$versionId.content'),
        );
        if (await contentFile.exists()) {
          await contentFile.delete();
        }
      }
    } catch (_) {
      // 清理失败不影响主流程
    }
  }

  /// 生成路径哈希（用于创建子目录）
  String _hashPath(String path) {
    var hash = 0;
    for (var i = 0; i < path.length; i++) {
      hash = ((hash << 5) - hash) + path.codeUnitAt(i);
      hash = hash & 0x7FFFFFFF; // 保持正数
    }
    // 返回路径最后一段 + hash，便于人工识别
    final basename = p.basenameWithoutExtension(path);
    final safeBasename = basename.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    // 修复边界条件 - 当 basename 为空时使用 'file' 作为前缀
    final prefix = safeBasename.isEmpty
        ? 'file'
        : safeBasename.substring(0, safeBasename.length.clamp(0, 20));
    return '${prefix}_$hash';
  }

  /// 读取指定版本的文件内容
  ///
  /// 返回 (内容, 元数据)，如果版本不存在则返回 (null, null)
  Future<(String?, FileVersionInfo?)> readVersionContent({
    required String filePath,
    required String versionId,
  }) async {
    try {
      final historyDir = await _getHistoryDir();
      final normalizedPath = p.normalize(filePath);
      final pathHash = _hashPath(normalizedPath);
      final fileHistoryDir = Directory(p.join(historyDir.path, pathHash));

      final contentFile = File(
        p.join(fileHistoryDir.path, '$versionId.content'),
      );
      if (!await contentFile.exists()) {
        return (null, null);
      }

      final content = await contentFile.readAsString();

      // 尝试读取元数据
      FileVersionInfo? metadata;
      final metaFile = File(
        p.join(fileHistoryDir.path, '$versionId.meta.json'),
      );
      if (await metaFile.exists()) {
        try {
          final metaContent = await metaFile.readAsString();
          final meta = jsonDecode(metaContent) as Map<String, Object?>;
          metadata = FileVersionInfo.fromJson(meta);
        } catch (error, stack) {
          silentLog(
            'ai_file_history_service',
            'parse version meta',
            error,
            stack,
          );
        }
      }

      return (content, metadata);
    } catch (e) {
      return (null, null);
    }
  }

  /// 清理指定会话的所有历史记录
  Future<void> clearSessionHistory(String sessionId) async {
    try {
      final historyDir = await _getHistoryDir();
      await for (final pathDir in historyDir.list()) {
        if (pathDir is! Directory) continue;
        await for (final file in pathDir.list()) {
          if (file is! File || !file.path.endsWith('.meta.json')) continue;
          try {
            final content = await file.readAsString();
            final meta = jsonDecode(content) as Map<String, Object?>;
            if (meta['session_id'] == sessionId) {
              final versionId = meta['version_id'] as String?;
              if (versionId != null) {
                await file.delete();
                final contentFile = File(
                  p.join(pathDir.path, '$versionId.content'),
                );
                if (await contentFile.exists()) {
                  await contentFile.delete();
                }
              }
            }
          } catch (error, stack) {
            silentLog(
              'ai_file_history_service',
              'clear single history file',
              error,
              stack,
            );
          }
        }
      }
    } catch (error, stack) {
      silentLog(
        'ai_file_history_service',
        'iterate history dir for clear',
        error,
        stack,
      );
    }
  }
}

/// 文件版本信息
class FileVersionInfo {
  const FileVersionInfo({
    required this.versionId,
    required this.filePath,
    required this.sessionId,
    required this.createdAt,
    this.toolCallId,
    this.fileSizeBytes,
  });

  factory FileVersionInfo.fromJson(Map<String, Object?> json) {
    return FileVersionInfo(
      versionId: json['version_id'] as String? ?? '',
      filePath: json['file_path'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      toolCallId: json['tool_call_id'] as String?,
      fileSizeBytes: json['file_size_bytes'] as int?,
    );
  }

  final String versionId;
  final String filePath;
  final String sessionId;
  final DateTime createdAt;
  final String? toolCallId;
  final int? fileSizeBytes;
}

/// 回滚结果
class RollbackResult {
  const RollbackResult.success(this.versionId)
    : success = true,
      errorMessage = '';
  const RollbackResult.failure(this.errorMessage)
    : success = false,
      versionId = '';

  final bool success;
  final String versionId;
  final String errorMessage;
}
