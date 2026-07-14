import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/path_safety.dart';
import '../../../../shared/util/rolling_hash.dart';
import '../../../../shared/util/text_clip.dart';

/// 文件编辑历史版本服务
///
/// 核心机制：
/// 1. 每次 Edit/Write 前保存文件当前内容的快照
/// 2. 每个文件保留最近 N 个版本
/// 3. 支持回滚到指定版本
class AiFileHistoryService {
  AiFileHistoryService({String? historyDirectory, this.maxVersionsPerFile = 10})
    : _historyDirectory = historyDirectory == null
          ? null
          : p.normalize(historyDirectory.trim()) {
    if (historyDirectory != null && nullIfBlank(historyDirectory) == null) {
      throw ArgumentError.value(
        historyDirectory,
        'historyDirectory',
        'Must not be blank.',
      );
    }
    if (maxVersionsPerFile < 1 || maxVersionsPerFile > _maxVersionsPerFile) {
      throw ArgumentError.value(
        maxVersionsPerFile,
        'maxVersionsPerFile',
        'Must be between 1 and $_maxVersionsPerFile.',
      );
    }
  }

  static final RegExp _unsafeHistoryPathBasenamePattern = RegExp(
    r'[^a-zA-Z0-9_-]',
  );
  static const int _historyPathBasenamePrefixLength = 20;
  static const int _maxVersionsPerFile = 1000;
  static const int _maxVersionSuffixCharacters = 80;
  static const int _maxVersionIdCharacters = 160;
  static const int _maxMetadataIdentifierCharacters = 512;
  static const int _maxHistoryContentBytes = 16 * kBytesPerMiB;
  static const int _maxHistoryMetadataBytes = 64 * kBytesPerKiB;
  static const int _maxHistoryDirectoryEntries = 4096;
  static const int _maxHistoryRootDirectories = 10000;
  static const int _maxSessionClearEntries = 100000;
  static const Duration _historyScanTimeout = Duration(seconds: 10);
  static const Duration _sessionClearTimeout = Duration(seconds: 30);
  static const Duration _orphanContentGracePeriod = Duration(hours: 1);

  final String? _historyDirectory;
  final int maxVersionsPerFile;
  int _versionSerial = 0;

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
      final location = await _resolveFileHistoryLocation(
        filePath,
        create: true,
      );
      final fileHistoryDir = location.directory;

      // 版本 ID = 时间戳 + UUID 后缀
      final timestamp = DateTime.now().toUtc();
      final normalizedToolCallId = nullIfBlank(toolCallId);
      final suffix = sanitizePortableFileNamePart(
        normalizedToolCallId ?? 'manual',
        fallback: 'manual',
        maxCharacters: _maxVersionSuffixCharacters,
        collapseReplacement: true,
        trimBoundaryReplacement: true,
      );
      final versionId =
          '${timestamp.microsecondsSinceEpoch}_${_versionSerial++}_$suffix';

      // 读取当前内容
      final content = await readBoundedFileString(
        file,
        maxBytes: _maxHistoryContentBytes,
      );

      // 保存版本元数据
      final versionMetadata = <String, Object?>{
        'version_id': versionId,
        'file_path': location.normalizedPath,
        'session_id': clipText(
          sessionId,
          _maxMetadataIdentifierCharacters,
          suffix: '',
        ),
        'tool_call_id': normalizedToolCallId == null
            ? null
            : clipText(
                normalizedToolCallId,
                _maxMetadataIdentifierCharacters,
                suffix: '',
              ),
        'created_at': timestamp.toIso8601String(),
        'file_size_bytes': utf8.encode(content).length,
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
      try {
        await writeFileAtomically(metadataFile, jsonEncode(versionMetadata));
      } catch (_) {
        try {
          if (await contentFile.exists()) await contentFile.delete();
        } on FileSystemException {
          // Preserve the metadata write failure as the primary result.
        }
        rethrow;
      }

      // 清理旧版本
      await _pruneOldVersions(fileHistoryDir);

      return versionId;
    } catch (_) {
      // 历史版本保存失败不应阻断编辑操作
      return null;
    }
  }

  /// 获取文件的版本历史列表
  Future<List<FileVersionInfo>> getVersionHistory(String filePath) async {
    try {
      final fileHistoryDir = (await _resolveFileHistoryLocation(
        filePath,
      )).directory;

      if (!await fileHistoryDir.exists()) {
        return const <FileVersionInfo>[];
      }

      final versions = <FileVersionInfo>[];
      final metaFiles = <File>[];
      final contentFiles = <File>[];
      final listing = await listDirectoryBounded(
        fileHistoryDir,
        maxEntries: _maxHistoryDirectoryEntries,
      );
      for (final entity in listing.entries) {
        if (entity is File && entity.path.endsWith('.meta.json')) {
          metaFiles.add(entity);
          try {
            final metaContent = await readBoundedFileString(
              entity,
              maxBytes: _maxHistoryMetadataBytes,
            );
            final info = _decodeVersionInfo(metaContent);
            if (info != null &&
                _isSafeVersionId(info.versionId) &&
                p.basename(entity.path) == '${info.versionId}.meta.json' &&
                p.equals(info.filePath, p.normalize(filePath))) {
              versions.add(info);
            }
          } catch (_) {
            // 跳过损坏的元数据文件
          }
        } else if (entity is File && entity.path.endsWith('.content')) {
          contentFiles.add(entity);
        }
      }
      if (!listing.truncated) {
        await _deleteStaleOrphanContentFiles(metaFiles, contentFiles);
      }

      // 按时间倒序排列
      versions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return versions.take(maxVersionsPerFile).toList(growable: false);
    } catch (_) {
      return const <FileVersionInfo>[];
    }
  }

  /// 回滚到指定版本
  Future<RollbackResult> rollbackToVersion({
    required String filePath,
    required String versionId,
  }) async {
    if (!_isSafeVersionId(versionId)) {
      return const RollbackResult.failure('Invalid version ID');
    }
    try {
      final (historicContent, _) = await readVersionContent(
        filePath: filePath,
        versionId: versionId,
      );
      if (historicContent == null) {
        return const RollbackResult.failure('Version not found');
      }

      final location = await _resolveFileHistoryLocation(filePath);
      final targetFile = File(location.normalizedPath);
      if (await targetFile.exists()) {
        final backupId = await saveVersion(
          filePath: filePath,
          sessionId: 'rollback-backup',
          toolCallId: 'pre-rollback-${DateTime.now().millisecondsSinceEpoch}',
        );
        if (backupId == null) {
          return const RollbackResult.failure(
            'Could not save the current file before rollback',
          );
        }
      }

      // 恢复历史版本
      await writeFileAtomically(targetFile, historicContent);

      return RollbackResult.success(versionId);
    } catch (e) {
      return RollbackResult.failure('Rollback failed: $e');
    }
  }

  /// 清理超出限制的旧版本
  Future<void> _pruneOldVersions(Directory fileHistoryDir) async {
    try {
      final metaFiles = <File>[];
      final contentFiles = <File>[];
      final listing = await listDirectoryBounded(
        fileHistoryDir,
        maxEntries: _maxHistoryDirectoryEntries,
      );
      if (listing.truncated) return;
      for (final entity in listing.entries) {
        if (entity is File && entity.path.endsWith('.meta.json')) {
          metaFiles.add(entity);
        } else if (entity is File && entity.path.endsWith('.content')) {
          contentFiles.add(entity);
        }
      }
      await _deleteStaleOrphanContentFiles(metaFiles, contentFiles);

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

  Future<void> _deleteStaleOrphanContentFiles(
    List<File> metaFiles,
    List<File> contentFiles,
  ) async {
    final metadataVersionIds = metaFiles.map((file) {
      final name = p.basename(file.path);
      return name.substring(0, name.length - '.meta.json'.length);
    }).toSet();
    final orphanCutoff = DateTime.now().subtract(_orphanContentGracePeriod);
    final contentVersionIds = <String>{
      for (final file in contentFiles)
        p
            .basename(file.path)
            .substring(0, p.basename(file.path).length - '.content'.length),
    };
    for (final contentFile in contentFiles) {
      final name = p.basename(contentFile.path);
      final versionId = name.substring(0, name.length - '.content'.length);
      if (metadataVersionIds.contains(versionId)) continue;
      try {
        final stat = await contentFile.stat();
        if (stat.modified.isBefore(orphanCutoff)) {
          await contentFile.delete();
        }
      } on FileSystemException {
        // Bounded orphan cleanup is best effort.
      }
    }
    for (final metaFile in metaFiles) {
      final name = p.basename(metaFile.path);
      final versionId = name.substring(0, name.length - '.meta.json'.length);
      if (contentVersionIds.contains(versionId)) continue;
      try {
        final stat = await metaFile.stat();
        if (stat.modified.isBefore(orphanCutoff)) {
          await metaFile.delete();
        }
      } on FileSystemException {
        // Bounded orphan cleanup is best effort.
      }
    }
  }

  String _historyDirectoryName(String path) {
    final digest = sha256.convert(utf8.encode(path)).toString();
    return '${_historyDirectoryPrefix(path)}_$digest';
  }

  /// Retains compatibility with directories created before SHA-256 keys.
  String _legacyHistoryDirectoryName(String path) {
    final hash = rollingHashPositive31Bit(
      path.codeUnits,
      (codeUnit) => codeUnit,
    );
    return '${_historyDirectoryPrefix(path)}_$hash';
  }

  String _historyDirectoryPrefix(String path) {
    final basename = p.basenameWithoutExtension(path);
    final safeBasename = basename.replaceAll(
      _unsafeHistoryPathBasenamePattern,
      '_',
    );
    final prefix = safeBasename.isEmpty
        ? 'file'
        : safeBasename.substring(
            0,
            safeBasename.length.clamp(0, _historyPathBasenamePrefixLength),
          );
    return prefix;
  }

  Future<({Directory directory, String normalizedPath})>
  _resolveFileHistoryLocation(String filePath, {bool create = false}) async {
    final historyDir = await _getHistoryDir();
    final normalizedPath = p.normalize(filePath);
    final directory = Directory(
      p.join(historyDir.path, _historyDirectoryName(normalizedPath)),
    );
    if (!await directory.exists()) {
      final legacyDirectory = Directory(
        p.join(historyDir.path, _legacyHistoryDirectoryName(normalizedPath)),
      );
      if (await legacyDirectory.exists()) {
        return (directory: legacyDirectory, normalizedPath: normalizedPath);
      }
    }
    if (create && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    return (directory: directory, normalizedPath: normalizedPath);
  }

  /// 读取指定版本的文件内容
  ///
  /// 返回 (内容, 元数据)，如果版本不存在则返回 (null, null)
  Future<(String?, FileVersionInfo?)> readVersionContent({
    required String filePath,
    required String versionId,
  }) async {
    if (!_isSafeVersionId(versionId)) {
      return (null, null);
    }
    try {
      final location = await _resolveFileHistoryLocation(filePath);
      final fileHistoryDir = location.directory;

      final contentFile = File(
        p.join(fileHistoryDir.path, '$versionId.content'),
      );
      if (!await contentFile.exists()) {
        return (null, null);
      }

      final metaFile = File(
        p.join(fileHistoryDir.path, '$versionId.meta.json'),
      );
      if (!await metaFile.exists()) {
        return (null, null);
      }
      final metaContent = await readBoundedFileString(
        metaFile,
        maxBytes: _maxHistoryMetadataBytes,
      );
      final metadata = _decodeVersionInfo(metaContent);
      if (metadata == null ||
          metadata.versionId != versionId ||
          !p.equals(metadata.filePath, location.normalizedPath)) {
        return (null, null);
      }
      final content = await readBoundedFileString(
        contentFile,
        maxBytes: _maxHistoryContentBytes,
      );

      return (content, metadata);
    } catch (error, stack) {
      silentLog(
        'ai_file_history_service',
        'read version content',
        error,
        stack,
      );
      return (null, null);
    }
  }

  /// 清理指定会话的所有历史记录
  Future<void> clearSessionHistory(String sessionId) async {
    try {
      final historyDir = await _getHistoryDir();
      final rootListing = await listDirectoryBounded(
        historyDir,
        maxEntries: _maxHistoryRootDirectories,
      );
      final stopwatch = Stopwatch()..start();
      var scannedEntries = 0;
      for (final pathDir in rootListing.entries) {
        if (scannedEntries >= _maxSessionClearEntries ||
            stopwatch.elapsed >= _sessionClearTimeout) {
          break;
        }
        if (pathDir is! Directory) continue;
        final remaining = _sessionClearTimeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) break;
        final listing = await listDirectoryBounded(
          pathDir,
          maxEntries: _maxHistoryDirectoryEntries,
          totalTimeout: remaining < _historyScanTimeout
              ? remaining
              : _historyScanTimeout,
        );
        for (final file in listing.entries) {
          scannedEntries += 1;
          if (scannedEntries > _maxSessionClearEntries) break;
          if (file is! File || !file.path.endsWith('.meta.json')) continue;
          try {
            final content = await readBoundedFileString(
              file,
              maxBytes: _maxHistoryMetadataBytes,
            );
            final info = _decodeVersionInfo(content);
            if (info?.sessionId == sessionId &&
                _isSafeVersionId(info!.versionId) &&
                p.basename(file.path) == '${info.versionId}.meta.json') {
              await file.delete();
              final contentFile = File(
                p.join(pathDir.path, '${info.versionId}.content'),
              );
              if (await contentFile.exists()) {
                await contentFile.delete();
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

  bool _isSafeVersionId(String versionId) {
    if (versionId.isEmpty ||
        versionId.length > _maxVersionIdCharacters ||
        versionId == '.' ||
        versionId == '..' ||
        versionId.contains('\u0000')) {
      return false;
    }
    return p.basename(versionId) == versionId &&
        p.posix.basename(versionId) == versionId &&
        p.windows.basename(versionId) == versionId;
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
      versionId: nullIfBlank(json['version_id']?.toString()) ?? '',
      filePath: nullIfBlank(json['file_path']?.toString()) ?? '',
      sessionId: nullIfBlank(json['session_id']?.toString()) ?? '',
      createdAt: dateTimeFromValue(json['created_at']) ?? DateTime.now(),
      toolCallId: nullIfBlank(json['tool_call_id']?.toString()),
      fileSizeBytes: optionalNonNegativeIntFromValue(json['file_size_bytes']),
    );
  }

  final String versionId;
  final String filePath;
  final String sessionId;
  final DateTime createdAt;
  final String? toolCallId;
  final int? fileSizeBytes;
}

FileVersionInfo? _decodeVersionInfo(String content) {
  final decoded = jsonDecode(content);
  if (decoded is! Map) return null;
  final info = FileVersionInfo.fromJson(stringKeyedMapFromValue(decoded));
  return info.versionId.isEmpty ? null : info;
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
