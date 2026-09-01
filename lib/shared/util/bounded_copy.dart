import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'argument_guards.dart';
import 'async_concurrency.dart';
import 'bounded_delete.dart';
import 'bounded_directory_io.dart';
import 'bounded_file_io.dart';
import 'path_safety.dart';
import 'physical_path_safety.dart';

const String _boundedCopyStagingPrefix = '.openhand-copy-';

final class BoundedCopyPolicy {
  const BoundedCopyPolicy({
    required this.maxEntries,
    required this.maxBytes,
    required this.maxDepth,
    this.directoryIdleTimeout = defaultBoundedDirectoryIdleTimeout,
    this.operationTimeout = const Duration(seconds: 30),
    this.totalTimeout = const Duration(minutes: 2),
  });

  final int maxEntries;
  final int maxBytes;
  final int maxDepth;
  final Duration directoryIdleTimeout;
  final Duration operationTimeout;
  final Duration totalTimeout;

  void validate() {
    requirePositiveInt(maxEntries, 'maxEntries');
    requirePositiveInt(maxBytes, 'maxBytes');
    requireNonNegativeInt(maxDepth, 'maxDepth');
    requirePositiveDuration(directoryIdleTimeout, 'directoryIdleTimeout');
    requirePositiveDuration(operationTimeout, 'operationTimeout');
    requirePositiveDuration(totalTimeout, 'totalTimeout');
  }
}

final class BoundedDirectoryCopyResult {
  const BoundedDirectoryCopyResult({
    required this.entryCount,
    required this.fileCount,
    required this.directoryCount,
    required this.totalBytes,
  });

  final int entryCount;
  final int fileCount;
  final int directoryCount;
  final int totalBytes;
}

/// 通过有界预检后再复制目录树；先写入同级暂存目录，再以重命名原子发布。
Future<BoundedDirectoryCopyResult> copyDirectoryBounded(
  Directory source,
  Directory target, {
  required BoundedCopyPolicy policy,
  bool allowExistingEmptyTarget = false,
}) async {
  policy.validate();
  final deadline = _CopyDeadline(policy);
  final sourcePath = p.normalize(p.absolute(source.path));
  final targetPath = p.normalize(p.absolute(target.path));
  if (p.equals(sourcePath, targetPath) || p.isWithin(sourcePath, targetPath)) {
    throw FileSystemException('复制目标不能是源目录或其子目录。', targetPath);
  }
  if (await isPhysicalPathWithinOrEqual(
    sourcePath,
    targetPath,
  ).timeout(deadline.nextOperationTimeout())) {
    throw FileSystemException('复制目标的物理路径位于源目录内。', targetPath);
  }

  final sourceType = await _entityType(sourcePath, deadline);
  if (sourceType != FileSystemEntityType.directory) {
    throw FileSystemException('复制源必须是普通目录，不能是符号链接。', sourcePath);
  }
  final targetTypeAtStart = await _validateTarget(
    targetPath,
    allowExistingEmptyTarget: allowExistingEmptyTarget,
    deadline: deadline,
  );
  await _requireDirectoryPath(p.dirname(targetPath), deadline);

  final plan = await _buildDirectoryPlan(
    Directory(sourcePath),
    policy,
    deadline,
  );
  Directory? stagingDirectory;
  Future<File>? pendingCopy;
  try {
    stagingDirectory = await _createBoundedCopyStagingDirectory(
      p.dirname(targetPath),
      deadline,
    );

    for (final relativePath in plan.directories) {
      final destinationPath = p.join(stagingDirectory.path, relativePath);
      if (!isPathWithinOrEqual(stagingDirectory.path, destinationPath)) {
        throw FileSystemException('复制目标路径不安全。', relativePath);
      }
      await Directory(
        destinationPath,
      ).create().timeout(deadline.nextOperationTimeout());
    }

    for (final file in plan.files) {
      final destinationPath = p.join(stagingDirectory.path, file.relativePath);
      if (!isPathWithinOrEqual(stagingDirectory.path, destinationPath)) {
        throw FileSystemException('复制目标路径不安全。', file.relativePath);
      }
      final copyFuture = _copyPlannedFile(
        file,
        File(destinationPath),
        deadline,
      );
      try {
        await copyFuture.timeout(deadline.nextOperationTimeout());
      } on TimeoutException {
        pendingCopy = copyFuture;
        rethrow;
      }
    }

    await _prepareTargetForPublish(
      targetPath,
      targetTypeAtStart: targetTypeAtStart,
      deadline: deadline,
    );
    final staged = stagingDirectory;
    final renameFuture = staged.rename(targetPath);
    try {
      await renameFuture.timeout(deadline.nextOperationTimeout());
      stagingDirectory = null;
    } on TimeoutException {
      stagingDirectory = null;
      _retainLateDirectoryRename(renameFuture, staged);
      rethrow;
    }

    return BoundedDirectoryCopyResult(
      entryCount: plan.entryCount,
      fileCount: plan.files.length,
      directoryCount: plan.directories.length,
      totalBytes: plan.totalBytes,
    );
  } catch (_) {
    final staged = stagingDirectory;
    if (staged != null) {
      if (pendingCopy case final copyFuture?) {
        _deleteDirectoryAfterPendingCopy(copyFuture, staged);
      } else {
        await _deleteDirectoryQuietly(staged);
      }
    }
    rethrow;
  } finally {
    deadline.stop();
  }
}

/// 通过私有暂存目录复制普通文件；拒绝覆盖既有目标，也不隐式跟随符号链接。
Future<void> copyFileBounded(
  File source,
  File target, {
  required BoundedCopyPolicy policy,
}) async {
  policy.validate();
  final deadline = _CopyDeadline(policy);
  final sourcePath = p.normalize(p.absolute(source.path));
  final targetPath = p.normalize(p.absolute(target.path));
  if (p.equals(sourcePath, targetPath)) {
    throw FileSystemException('复制目标不能与复制源相同。', targetPath);
  }

  Directory? stagingDirectory;
  Future<File>? pendingCopy;
  try {
    final sourceFile = File(sourcePath);
    final sourceStat = await _regularFileStat(sourceFile, deadline);
    if (sourceStat.size > policy.maxBytes) {
      throw FileSystemException('复制源超过字节上限。', sourcePath);
    }
    final targetType = await _entityType(targetPath, deadline);
    if (targetType != FileSystemEntityType.notFound) {
      throw FileSystemException('复制目标已存在。', targetPath);
    }
    await _requireDirectoryPath(p.dirname(targetPath), deadline);

    stagingDirectory = await _createBoundedCopyStagingDirectory(
      p.dirname(targetPath),
      deadline,
    );
    final stagedFile = File(p.join(stagingDirectory.path, 'payload'));
    final copyFuture = _copyPlannedFile(
      _PlannedFile(
        source: sourceFile,
        relativePath: p.basename(targetPath),
        stat: sourceStat,
      ),
      stagedFile,
      deadline,
    );
    try {
      await copyFuture.timeout(deadline.nextOperationTimeout());
    } on TimeoutException {
      pendingCopy = copyFuture;
      rethrow;
    }

    if (await _entityType(targetPath, deadline) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('复制目标已存在。', targetPath);
    }
    final staged = stagingDirectory;
    final renameFuture = stagedFile.rename(targetPath);
    try {
      await renameFuture.timeout(deadline.nextOperationTimeout());
      await _deleteDirectoryQuietly(staged);
      stagingDirectory = null;
    } on TimeoutException {
      stagingDirectory = null;
      _cleanupAfterLateFileRename(renameFuture, staged);
      rethrow;
    }
  } catch (_) {
    final staged = stagingDirectory;
    if (staged != null) {
      if (pendingCopy case final copyFuture?) {
        _deleteDirectoryAfterPendingCopy(copyFuture, staged);
      } else {
        await _deleteDirectoryQuietly(staged);
      }
    }
    rethrow;
  } finally {
    deadline.stop();
  }
}

Future<_DirectoryCopyPlan> _buildDirectoryPlan(
  Directory source,
  BoundedCopyPolicy policy,
  _CopyDeadline deadline,
) async {
  final directories = <String>[];
  final files = <_PlannedFile>[];
  final pending = Queue<_PendingDirectory>()
    ..add(_PendingDirectory(directory: source, relativePath: '', depth: 0));
  var entryCount = 0;
  var totalBytes = 0;

  while (pending.isNotEmpty) {
    final current = pending.removeFirst();
    final remainingEntries = policy.maxEntries - entryCount;
    final remainingTime = deadline.remaining();
    final idleTimeout = deadline.directoryIdleTimeout(remainingTime);
    final listing = await listDirectoryBounded(
      current.directory,
      maxEntries: remainingEntries + 1,
      idleTimeout: idleTimeout,
      totalTimeout: remainingTime,
    );
    if (listing.truncated) {
      throw FileSystemException('复制源目录扫描超过时间或条目数量上限。', current.directory.path);
    }

    for (final entity in listing.entries) {
      entryCount += 1;
      if (entryCount > policy.maxEntries) {
        throw FileSystemException('复制源包含过多条目。', source.path);
      }
      final name = p.basename(entity.path);
      if (name.isEmpty || name == '.' || name == '..') {
        throw FileSystemException('复制源包含不安全的名称。', entity.path);
      }
      final relativePath = current.relativePath.isEmpty
          ? name
          : p.join(current.relativePath, name);
      final type = await _entityType(entity.path, deadline);
      switch (type) {
        case FileSystemEntityType.directory:
          final depth = current.depth + 1;
          if (depth > policy.maxDepth) {
            throw FileSystemException('复制源超过目录深度上限。', entity.path);
          }
          directories.add(relativePath);
          pending.add(
            _PendingDirectory(
              directory: Directory(entity.path),
              relativePath: relativePath,
              depth: depth,
            ),
          );
        case FileSystemEntityType.file:
          final file = File(entity.path);
          final stat = await _regularFileStat(file, deadline);
          if (stat.size > policy.maxBytes - totalBytes) {
            throw FileSystemException('复制源超过字节上限。', entity.path);
          }
          totalBytes += stat.size;
          files.add(
            _PlannedFile(source: file, relativePath: relativePath, stat: stat),
          );
        case FileSystemEntityType.link:
          throw FileSystemException('复制源不能包含符号链接。', entity.path);
        case FileSystemEntityType.notFound:
          throw FileSystemException('复制源在扫描期间发生变化。', entity.path);
        case FileSystemEntityType.pipe:
        case FileSystemEntityType.unixDomainSock:
          throw FileSystemException('复制源包含不支持的文件系统条目。', entity.path);
      }
    }
  }

  return _DirectoryCopyPlan(
    directories: directories,
    files: files,
    entryCount: entryCount,
    totalBytes: totalBytes,
  );
}

Future<File> _copyPlannedFile(
  _PlannedFile planned,
  File destination,
  _CopyDeadline deadline,
) async {
  final currentStat = await _regularFileStat(planned.source, deadline);
  if (!_sameFileVersion(planned.stat, currentStat)) {
    throw FileSystemException('复制源在扫描后发生变化。', planned.source.path);
  }
  final copied = await planned.source.copy(destination.path);
  final copiedStat = await _regularFileStat(copied, deadline);
  final finalSourceStat = await _regularFileStat(planned.source, deadline);
  if (copiedStat.size != planned.stat.size ||
      !_sameFileVersion(planned.stat, finalSourceStat)) {
    throw FileSystemException('复制源在复制期间发生变化。', planned.source.path);
  }
  return copied;
}

bool _sameFileVersion(FileStat expected, FileStat actual) {
  return expected.size == actual.size &&
      expected.modified == actual.modified &&
      expected.changed == actual.changed;
}

Future<FileStat> _regularFileStat(File file, _CopyDeadline deadline) async {
  final type = await _entityType(file.path, deadline);
  if (type != FileSystemEntityType.file) {
    throw FileSystemException('复制源必须是普通文件，不能是符号链接。', file.path);
  }
  final stat = await file.stat().timeout(deadline.nextOperationTimeout());
  if (!isRegularFileStat(stat)) {
    throw FileSystemException('复制源不是普通文件。', file.path);
  }
  return stat;
}

Future<FileSystemEntityType> _validateTarget(
  String targetPath, {
  required bool allowExistingEmptyTarget,
  required _CopyDeadline deadline,
}) async {
  final targetType = await _entityType(targetPath, deadline);
  if (targetType == FileSystemEntityType.notFound) return targetType;
  if (targetType != FileSystemEntityType.directory ||
      !allowExistingEmptyTarget) {
    throw FileSystemException('复制目标已存在。', targetPath);
  }
  await _requireEmptyDirectory(Directory(targetPath), deadline);
  return targetType;
}

Future<void> _prepareTargetForPublish(
  String targetPath, {
  required FileSystemEntityType targetTypeAtStart,
  required _CopyDeadline deadline,
}) async {
  final currentType = await _entityType(targetPath, deadline);
  if (targetTypeAtStart == FileSystemEntityType.notFound) {
    if (currentType != FileSystemEntityType.notFound) {
      throw FileSystemException('复制目标被并发创建。', targetPath);
    }
    return;
  }
  if (currentType == FileSystemEntityType.notFound) return;
  if (currentType != FileSystemEntityType.directory) {
    throw FileSystemException('复制目标在操作期间发生变化。', targetPath);
  }
  final target = Directory(targetPath);
  await _requireEmptyDirectory(target, deadline);
  await target.delete().timeout(deadline.nextOperationTimeout());
}

Future<void> _requireEmptyDirectory(
  Directory directory,
  _CopyDeadline deadline,
) async {
  final remaining = deadline.remaining();
  final listing = await listDirectoryBounded(
    directory,
    maxEntries: 1,
    idleTimeout: deadline.directoryIdleTimeout(remaining),
    totalTimeout: remaining,
  );
  if (listing.truncated || listing.entries.isNotEmpty) {
    throw FileSystemException('复制目标目录必须为空。', directory.path);
  }
}

Future<void> _requireDirectoryPath(String path, _CopyDeadline deadline) async {
  if (await _entityType(path, deadline) != FileSystemEntityType.directory) {
    throw FileSystemException('复制目标的父路径不是目录。', path);
  }
}

Future<FileSystemEntityType> _entityType(String path, _CopyDeadline deadline) {
  return FileSystemEntity.type(
    path,
    followLinks: false,
  ).timeout(deadline.nextOperationTimeout());
}

void _deleteDirectoryAfterPendingCopy(
  Future<File> pendingCopy,
  Directory stagingDirectory,
) {
  unawaited(
    pendingCopy
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() => _deleteDirectoryQuietly(stagingDirectory)),
  );
}

Future<Directory> _createBoundedCopyStagingDirectory(
  String parentPath,
  _CopyDeadline deadline,
) {
  return createTemporaryDirectoryBounded(
    parent: Directory(parentPath),
    prefix: _boundedCopyStagingPrefix,
    timeout: deadline.nextOperationTimeout(),
    allowedRoot: parentPath,
  );
}

void _retainLateDirectoryRename(
  Future<Directory> renameFuture,
  Directory stagingDirectory,
) {
  unawaited(
    renameFuture.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) =>
          _deleteDirectoryQuietly(stagingDirectory),
    ),
  );
}

void _cleanupAfterLateFileRename(
  Future<File> renameFuture,
  Directory stagingDirectory,
) {
  unawaited(
    renameFuture
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() => _deleteDirectoryQuietly(stagingDirectory)),
  );
}

Future<void> _deleteDirectoryQuietly(Directory directory) async {
  try {
    await deletePathBounded(p.absolute(directory.path));
  } catch (_) {
    // 暂存目录清理失败不能覆盖原始复制异常。
  }
}

final class _CopyDeadline {
  _CopyDeadline(this.policy)
    : _deadline = MonotonicDeadline(
        policy.totalTimeout,
        timeoutMessage: '复制操作超过总时限。',
      );

  final BoundedCopyPolicy policy;
  final MonotonicDeadline _deadline;

  Duration remaining() => _deadline.remaining();

  Duration nextOperationTimeout() => _deadline.limit(policy.operationTimeout);

  Duration directoryIdleTimeout(Duration remainingTime) {
    return remainingTime < policy.directoryIdleTimeout
        ? remainingTime
        : policy.directoryIdleTimeout;
  }

  void stop() => _deadline.stop();
}

final class _PendingDirectory {
  const _PendingDirectory({
    required this.directory,
    required this.relativePath,
    required this.depth,
  });

  final Directory directory;
  final String relativePath;
  final int depth;
}

final class _PlannedFile {
  const _PlannedFile({
    required this.source,
    required this.relativePath,
    required this.stat,
  });

  final File source;
  final String relativePath;
  final FileStat stat;
}

final class _DirectoryCopyPlan {
  const _DirectoryCopyPlan({
    required this.directories,
    required this.files,
    required this.entryCount,
    required this.totalBytes,
  });

  final List<String> directories;
  final List<_PlannedFile> files;
  final int entryCount;
  final int totalBytes;
}
