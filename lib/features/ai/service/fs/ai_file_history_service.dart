import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/path_safety.dart';
import '../../../../shared/util/rolling_hash.dart';
import '../../../../shared/util/text_clip.dart';
import '../../model/ai_session_message.dart';

/// 文件编辑历史版本服务
///
/// 核心机制：
/// 1. 每次 Edit/Write 前保存文件当前内容的快照
/// 2. 每个文件保留最近 N 个版本
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
    '[^a-zA-Z0-9_-]',
  );
  static const int _historyPathBasenamePrefixLength = 20;
  static const String _metadataFileSuffix = '.meta.json';
  static const String _contentFileSuffix = '.content';
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
  Future<Directory> _getHistoryDir({
    required MonotonicDeadline deadline,
  }) async {
    final baseDir =
        _historyDirectory ??
        p.join(
          OpenHandPaths.defaultRootDirectoryPath(),
          'file_history',
          'legacy_versions',
        );
    final dir = Directory(baseDir);
    if (!await dir.exists().timeout(_metadataTimeout(deadline))) {
      await dir.create(recursive: true).timeout(_metadataTimeout(deadline));
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
    final deadline = MonotonicDeadline(
      _historyScanTimeout,
      timeoutMessage: '准备文件历史版本超过总时限。',
    );
    try {
      if (!await file.exists().timeout(_metadataTimeout(deadline))) return null;
      final location = await _resolveFileHistoryLocation(
        filePath,
        create: true,
        deadline: deadline,
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
      final content = await _readHistoryText(
        file,
        maxBytes: _maxHistoryContentBytes,
        deadline: deadline,
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
        aiSessionMessageToolCallIdMetadataKey: normalizedToolCallId == null
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
        p.join(fileHistoryDir.path, '$versionId$_contentFileSuffix'),
      );
      await writeFileAtomically(contentFile, content);

      // 保存元数据文件
      final metadataFile = File(
        p.join(fileHistoryDir.path, '$versionId$_metadataFileSuffix'),
      );
      try {
        await writeFileAtomically(metadataFile, jsonEncode(versionMetadata));
      } catch (_) {
        try {
          if (await contentFile.exists().timeout(
            defaultBoundedFileReadIdleTimeout,
          )) {
            await contentFile.delete().timeout(
              defaultBoundedFileReadIdleTimeout,
            );
          }
        } catch (_) {
          // 保留元数据写入失败作为主结果。
        }
        rethrow;
      }

      // 清理旧版本
      await _pruneOldVersions(fileHistoryDir);

      return versionId;
    } catch (_) {
      // 历史版本保存失败不应阻断编辑操作
      return null;
    } finally {
      deadline.stop();
    }
  }

  /// 获取文件的版本历史列表
  Future<List<FileVersionInfo>> getVersionHistory(String filePath) async {
    final versions = <FileVersionInfo>[];
    final deadline = MonotonicDeadline(
      _historyScanTimeout,
      timeoutMessage: '读取文件历史版本超过总时限。',
    );
    try {
      final location = await _resolveFileHistoryLocation(
        filePath,
        deadline: deadline,
      );
      final fileHistoryDir = location.directory;

      if (!await fileHistoryDir.exists().timeout(_metadataTimeout(deadline))) {
        return const <FileVersionInfo>[];
      }

      final metaFiles = <File>[];
      final contentFiles = <File>[];
      final listing = await listDirectoryBounded(
        fileHistoryDir,
        maxEntries: _maxHistoryDirectoryEntries,
        totalTimeout: deadline.remaining(),
      );
      var scannedAllEntries = true;
      for (final entity in listing.entries) {
        if (deadline.isExpired) {
          scannedAllEntries = false;
          break;
        }
        if (entity is File && entity.path.endsWith(_metadataFileSuffix)) {
          metaFiles.add(entity);
          try {
            final metaContent = await _readHistoryText(
              entity,
              maxBytes: _maxHistoryMetadataBytes,
              deadline: deadline,
            );
            final info = _decodeVersionInfo(metaContent);
            if (info != null &&
                _isSafeVersionId(info.versionId) &&
                p.basename(entity.path) ==
                    '${info.versionId}$_metadataFileSuffix' &&
                p.equals(info.filePath, location.normalizedPath)) {
              versions.add(info);
            }
          } on TimeoutException {
            scannedAllEntries = false;
            break;
          } catch (_) {
            // 跳过损坏的元数据文件
          }
        } else if (entity is File && entity.path.endsWith(_contentFileSuffix)) {
          contentFiles.add(entity);
        }
      }
      if (!listing.truncated && scannedAllEntries && !deadline.isExpired) {
        await _deleteStaleOrphanContentFiles(metaFiles, contentFiles, deadline);
      }
    } catch (_) {
      // 返回时限内已解析的版本。
    } finally {
      deadline.stop();
    }
    versions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return versions.take(maxVersionsPerFile).toList(growable: false);
  }

  /// 清理超出限制的旧版本
  Future<void> _pruneOldVersions(Directory fileHistoryDir) async {
    final deadline = MonotonicDeadline(
      _historyScanTimeout,
      timeoutMessage: '清理文件历史版本超过总时限。',
    );
    try {
      final metaFiles = <File>[];
      final contentFiles = <File>[];
      final listing = await listDirectoryBounded(
        fileHistoryDir,
        maxEntries: _maxHistoryDirectoryEntries,
        totalTimeout: deadline.remaining(),
      );
      if (listing.truncated) return;
      for (final entity in listing.entries) {
        if (entity is File && entity.path.endsWith(_metadataFileSuffix)) {
          metaFiles.add(entity);
        } else if (entity is File && entity.path.endsWith(_contentFileSuffix)) {
          contentFiles.add(entity);
        }
      }
      await _deleteStaleOrphanContentFiles(metaFiles, contentFiles, deadline);

      if (metaFiles.length <= maxVersionsPerFile) return;

      // 按修改时间排序
      final fileStats = <File, DateTime>{};
      for (final file in metaFiles) {
        if (deadline.isExpired) return;
        try {
          final stat = await file.stat().timeout(_metadataTimeout(deadline));
          fileStats[file] = stat.modified;
        } on TimeoutException {
          return;
        } on FileSystemException {
          return;
        }
      }
      metaFiles.sort((a, b) => fileStats[b]!.compareTo(fileStats[a]!));

      // 删除超出限制的旧版本
      for (var i = maxVersionsPerFile; i < metaFiles.length; i++) {
        if (deadline.isExpired) return;
        final metaFile = metaFiles[i];
        final name = p.basename(metaFile.path);
        final versionId = name.substring(
          0,
          name.length - _metadataFileSuffix.length,
        );
        try {
          await metaFile.delete().timeout(_metadataTimeout(deadline));
          final contentFile = File(
            p.join(fileHistoryDir.path, '$versionId$_contentFileSuffix'),
          );
          if (await contentFile.exists().timeout(_metadataTimeout(deadline))) {
            await contentFile.delete().timeout(_metadataTimeout(deadline));
          }
        } on TimeoutException {
          return;
        } on FileSystemException {
          // 单个版本可能已被其他进程清理，继续处理剩余版本。
        }
      }
    } catch (_) {
      // 清理失败不影响主流程
    } finally {
      deadline.stop();
    }
  }

  Future<void> _deleteStaleOrphanContentFiles(
    List<File> metaFiles,
    List<File> contentFiles,
    MonotonicDeadline deadline,
  ) async {
    final metadataVersionIds = metaFiles.map((file) {
      final name = p.basename(file.path);
      return name.substring(0, name.length - _metadataFileSuffix.length);
    }).toSet();
    final orphanCutoff = DateTime.now().subtract(_orphanContentGracePeriod);
    final contentVersionIds = contentFiles.map((file) {
      final name = p.basename(file.path);
      return name.substring(0, name.length - _contentFileSuffix.length);
    }).toSet();
    for (final contentFile in contentFiles) {
      if (deadline.isExpired) return;
      final name = p.basename(contentFile.path);
      final versionId = name.substring(
        0,
        name.length - _contentFileSuffix.length,
      );
      if (metadataVersionIds.contains(versionId)) continue;
      try {
        final stat = await contentFile.stat().timeout(
          _metadataTimeout(deadline),
        );
        if (stat.modified.isBefore(orphanCutoff)) {
          await contentFile.delete().timeout(_metadataTimeout(deadline));
        }
      } on TimeoutException {
        return;
      } on FileSystemException {
        // 孤儿文件清理仅尽力执行。
      }
    }
    for (final metaFile in metaFiles) {
      if (deadline.isExpired) return;
      final name = p.basename(metaFile.path);
      final versionId = name.substring(
        0,
        name.length - _metadataFileSuffix.length,
      );
      if (contentVersionIds.contains(versionId)) continue;
      try {
        final stat = await metaFile.stat().timeout(_metadataTimeout(deadline));
        if (stat.modified.isBefore(orphanCutoff)) {
          await metaFile.delete().timeout(_metadataTimeout(deadline));
        }
      } on TimeoutException {
        return;
      } on FileSystemException {
        // 孤儿文件清理仅尽力执行。
      }
    }
  }

  String _historyDirectoryName(String path) {
    final digest = sha256.convert(utf8.encode(path)).toString();
    return '${_historyDirectoryPrefix(path)}_$digest';
  }

  /// 兼容迁移前使用旧哈希命名的历史目录。
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
  _resolveFileHistoryLocation(
    String filePath, {
    bool create = false,
    required MonotonicDeadline deadline,
  }) async {
    final historyDir = await _getHistoryDir(deadline: deadline);
    final normalizedPath = p.normalize(filePath);
    final directory = Directory(
      p.join(historyDir.path, _historyDirectoryName(normalizedPath)),
    );
    final directoryExists = await directory.exists().timeout(
      _metadataTimeout(deadline),
    );
    if (!directoryExists) {
      final legacyDirectory = Directory(
        p.join(historyDir.path, _legacyHistoryDirectoryName(normalizedPath)),
      );
      if (await legacyDirectory.exists().timeout(_metadataTimeout(deadline))) {
        return (directory: legacyDirectory, normalizedPath: normalizedPath);
      }
    }
    if (create && !directoryExists) {
      await directory
          .create(recursive: true)
          .timeout(_metadataTimeout(deadline));
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
    final deadline = MonotonicDeadline(
      _historyScanTimeout,
      timeoutMessage: '读取文件历史内容超过总时限。',
    );
    try {
      final location = await _resolveFileHistoryLocation(
        filePath,
        deadline: deadline,
      );
      final fileHistoryDir = location.directory;

      final contentFile = File(
        p.join(fileHistoryDir.path, '$versionId$_contentFileSuffix'),
      );
      if (!await contentFile.exists().timeout(_metadataTimeout(deadline))) {
        return (null, null);
      }

      final metaFile = File(
        p.join(fileHistoryDir.path, '$versionId$_metadataFileSuffix'),
      );
      if (!await metaFile.exists().timeout(_metadataTimeout(deadline))) {
        return (null, null);
      }
      final metaContent = await _readHistoryText(
        metaFile,
        maxBytes: _maxHistoryMetadataBytes,
        deadline: deadline,
      );
      final metadata = _decodeVersionInfo(metaContent);
      if (metadata == null ||
          metadata.versionId != versionId ||
          !p.equals(metadata.filePath, location.normalizedPath)) {
        return (null, null);
      }
      final content = await _readHistoryText(
        contentFile,
        maxBytes: _maxHistoryContentBytes,
        deadline: deadline,
      );

      return (content, metadata);
    } on TimeoutException {
      return (null, null);
    } catch (error, stack) {
      silentLog('ai_file_history_service', '读取版本内容', error, stack);
      return (null, null);
    } finally {
      deadline.stop();
    }
  }

  /// 清理指定会话的所有历史记录
  Future<void> clearSessionHistory(String sessionId) async {
    final deadline = MonotonicDeadline(
      _sessionClearTimeout,
      timeoutMessage: '清理会话文件历史超过总时限。',
    );
    try {
      final historyDir = await _getHistoryDir(deadline: deadline);
      final rootListing = await listDirectoryBounded(
        historyDir,
        maxEntries: _maxHistoryRootDirectories,
        totalTimeout: deadline.remaining(),
      );
      var scannedEntries = 0;
      for (final pathDir in rootListing.entries) {
        if (scannedEntries >= _maxSessionClearEntries || deadline.isExpired) {
          break;
        }
        if (pathDir is! Directory) continue;
        final listing = await listDirectoryBounded(
          pathDir,
          maxEntries: _maxHistoryDirectoryEntries,
          totalTimeout: deadline.limit(_historyScanTimeout),
        );
        for (final file in listing.entries) {
          scannedEntries += 1;
          if (scannedEntries > _maxSessionClearEntries || deadline.isExpired) {
            break;
          }
          if (file is! File || !file.path.endsWith(_metadataFileSuffix)) {
            continue;
          }
          try {
            final content = await _readHistoryText(
              file,
              maxBytes: _maxHistoryMetadataBytes,
              deadline: deadline,
            );
            final info = _decodeVersionInfo(content);
            if (info?.sessionId == sessionId &&
                _isSafeVersionId(info!.versionId) &&
                p.basename(file.path) ==
                    '${info.versionId}$_metadataFileSuffix') {
              await file.delete().timeout(_metadataTimeout(deadline));
              final contentFile = File(
                p.join(pathDir.path, '${info.versionId}$_contentFileSuffix'),
              );
              if (await contentFile.exists().timeout(
                _metadataTimeout(deadline),
              )) {
                await contentFile.delete().timeout(_metadataTimeout(deadline));
              }
            }
          } on TimeoutException {
            return;
          } catch (error, stack) {
            silentLog('ai_file_history_service', '清理单个历史文件', error, stack);
          }
        }
      }
    } on TimeoutException {
      return;
    } catch (error, stack) {
      silentLog('ai_file_history_service', '遍历待清理历史目录', error, stack);
    } finally {
      deadline.stop();
    }
  }

  Duration _metadataTimeout(MonotonicDeadline deadline) {
    return deadline.limit(defaultBoundedFileReadIdleTimeout);
  }

  Future<String> _readHistoryText(
    File file, {
    required int maxBytes,
    required MonotonicDeadline deadline,
  }) {
    final totalTimeout = deadline.remaining();
    return readBoundedFileString(
      file,
      maxBytes: maxBytes,
      idleTimeout: deadline.limit(defaultBoundedFileReadIdleTimeout),
      totalTimeout: totalTimeout,
    );
  }

  bool _isSafeVersionId(String versionId) {
    return isPortableFileNamePart(
      versionId,
      maxCodeUnits: _maxVersionIdCharacters,
    );
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
      toolCallId: nullIfBlank(
        json[aiSessionMessageToolCallIdMetadataKey]?.toString(),
      ),
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
