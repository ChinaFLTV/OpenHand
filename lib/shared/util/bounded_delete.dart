import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'argument_guards.dart';
import 'async_concurrency.dart';
import 'path_safety.dart';

const BoundedDeletePolicy defaultBoundedDeletePolicy = BoundedDeletePolicy(
  maxEntries: 100000,
  maxDepth: 128,
);

final class BoundedDeletePolicy {
  const BoundedDeletePolicy({
    required this.maxEntries,
    required this.maxDepth,
    this.directoryIdleTimeout = const Duration(seconds: 3),
    this.operationTimeout = const Duration(seconds: 10),
    this.totalTimeout = const Duration(minutes: 2),
  });

  final int maxEntries;
  final int maxDepth;
  final Duration directoryIdleTimeout;
  final Duration operationTimeout;
  final Duration totalTimeout;

  void validate() {
    requirePositiveInt(maxEntries, 'maxEntries');
    requireNonNegativeInt(maxDepth, 'maxDepth');
    requirePositiveDuration(directoryIdleTimeout, 'directoryIdleTimeout');
    requirePositiveDuration(operationTimeout, 'operationTimeout');
    requirePositiveDuration(totalTimeout, 'totalTimeout');
  }
}

enum BoundedDeleteFailureReason {
  invalidTarget,
  entryLimitExceeded,
  depthLimitExceeded,
  timeout,
  fileSystemFailure,
}

final class BoundedDeleteException extends FileSystemException {
  const BoundedDeleteException({
    required this.reason,
    required String message,
    required String path,
    required this.deletedEntries,
    required this.plannedEntries,
    this.cause,
  }) : super(message, path);

  final BoundedDeleteFailureReason reason;

  /// 发现异常前已确认删除的条目数。
  final int deletedEntries;

  /// 删除开始前由有界预检发现的条目数。
  final int plannedEntries;
  final Object? cause;
}

final class BoundedDeleteResult {
  const BoundedDeleteResult({
    required this.plannedEntries,
    required this.deletedEntries,
    required this.fileCount,
    required this.directoryCount,
    required this.linkCount,
    required this.wasMissing,
  });

  final int plannedEntries;
  final int deletedEntries;
  final int fileCount;
  final int directoryCount;
  final int linkCount;
  final bool wasMissing;
}

/// 删除一个绝对路径，不跟随符号链接，也不执行无界递归文件操作。
///
/// 目录树会在删除前完整预检；条目、深度、空闲、单步和总时限超限时不会部分删除。
/// 后序删除阶段若发生文件系统异常，可能留下部分结果，已删除数量由
/// [BoundedDeleteException.deletedEntries] 返回。
Future<BoundedDeleteResult> deletePathBounded(
  String path, {
  BoundedDeletePolicy policy = defaultBoundedDeletePolicy,
  bool allowMissing = true,
  String? allowedRoot,
}) async {
  policy.validate();
  final targetPath = _normalizeTargetPath(path);
  final allowedRootPath = allowedRoot == null
      ? null
      : _normalizeAllowedRoot(allowedRoot);
  if (allowedRootPath != null &&
      !isPathWithinOrEqual(allowedRootPath, targetPath)) {
    throw _invalidTarget(targetPath, '删除目标超出允许的根目录。');
  }
  final progress = _DeleteProgress(targetPath);
  final deadline = _DeleteDeadline(policy);

  try {
    final targetType = await _entityType(targetPath, deadline);
    if (targetType == FileSystemEntityType.notFound) {
      if (!allowMissing) {
        throw BoundedDeleteException(
          reason: BoundedDeleteFailureReason.fileSystemFailure,
          message: '删除目标不存在。',
          path: targetPath,
          deletedEntries: 0,
          plannedEntries: 0,
        );
      }
      return const BoundedDeleteResult(
        plannedEntries: 0,
        deletedEntries: 0,
        fileCount: 0,
        directoryCount: 0,
        linkCount: 0,
        wasMissing: true,
      );
    }

    String? physicalTarget;
    if (allowedRootPath != null) {
      final physicalRoot = p.normalize(
        await Directory(
          allowedRootPath,
        ).resolveSymbolicLinks().timeout(deadline.nextOperationTimeout()),
      );
      physicalTarget = await _physicalDeletionTarget(
        targetPath,
        targetType,
        deadline,
      );
      if (!isPathWithinOrEqual(physicalRoot, physicalTarget)) {
        throw _invalidTarget(targetPath, '删除目标的物理路径超出允许的根目录。');
      }
    }

    if (targetType != FileSystemEntityType.directory) {
      progress.plannedEntries = 1;
      await _deletePlannedPath(targetPath, progress, deadline);
      return progress.result();
    }

    physicalTarget ??= await _physicalDeletionTarget(
      targetPath,
      targetType,
      deadline,
    );
    _requireSafeNormalizedTarget(physicalTarget);

    final plan = await _buildDeletePlan(
      Directory(targetPath),
      policy,
      deadline,
      progress,
    );
    progress.plannedEntries = plan.entryCount;
    for (final entry in plan.nonDirectories) {
      await _deletePlannedPath(entry.path, progress, deadline);
    }
    for (final entry in plan.directories) {
      await _deletePlannedPath(entry.path, progress, deadline);
    }
    return progress.result();
  } on BoundedDeleteException {
    rethrow;
  } on TimeoutException catch (error, stack) {
    Error.throwWithStackTrace(
      BoundedDeleteException(
        reason: BoundedDeleteFailureReason.timeout,
        message: '有界删除超时，已确认删除 ${progress.deletedEntries} 个条目。',
        path: progress.activePath,
        deletedEntries: progress.deletedEntries,
        plannedEntries: progress.plannedEntries,
        cause: error,
      ),
      stack,
    );
  } on FileSystemException catch (error, stack) {
    Error.throwWithStackTrace(
      BoundedDeleteException(
        reason: BoundedDeleteFailureReason.fileSystemFailure,
        message:
            '有界删除失败，已确认删除 ${progress.deletedEntries} 个条目：'
            '${error.message}',
        path: error.path ?? progress.activePath,
        deletedEntries: progress.deletedEntries,
        plannedEntries: progress.plannedEntries,
        cause: error,
      ),
      stack,
    );
  } finally {
    deadline.stop();
  }
}

String _normalizeTargetPath(String path) {
  final rawPath = path.trim();
  if (rawPath.isEmpty || rawPath.contains('\u0000') || !p.isAbsolute(rawPath)) {
    throw _invalidTarget(rawPath, '删除目标必须是非空绝对路径。');
  }
  final normalized = p.normalize(rawPath);
  _requireSafeNormalizedTarget(normalized);
  return normalized;
}

String _normalizeAllowedRoot(String path) {
  final rawPath = path.trim();
  if (rawPath.isEmpty || rawPath.contains('\u0000') || !p.isAbsolute(rawPath)) {
    throw _invalidTarget(rawPath, '删除操作允许的根目录必须是非空绝对路径。');
  }
  return p.normalize(rawPath);
}

void _requireSafeNormalizedTarget(String targetPath) {
  final parentPath = p.dirname(targetPath);
  if (p.equals(parentPath, targetPath) ||
      _protectedDeletePaths().any(
        (protectedPath) => p.equals(protectedPath, targetPath),
      )) {
    throw _invalidTarget(targetPath, '拒绝删除受保护的文件系统路径。');
  }
}

BoundedDeleteException _invalidTarget(String path, String message) {
  return BoundedDeleteException(
    reason: BoundedDeleteFailureReason.invalidTarget,
    message: message,
    path: path,
    deletedEntries: 0,
    plannedEntries: 0,
  );
}

Set<String> _protectedDeletePaths() {
  final paths = <String>{
    p.normalize(p.absolute(Directory.current.path)),
    p.normalize(p.absolute(Directory.systemTemp.path)),
  };
  for (final variable in const <String>['HOME', 'USERPROFILE']) {
    final value = Platform.environment[variable]?.trim() ?? '';
    if (value.isNotEmpty && p.isAbsolute(value)) {
      paths.add(p.normalize(value));
    }
  }
  return paths;
}

Future<_DeletePlan> _buildDeletePlan(
  Directory root,
  BoundedDeletePolicy policy,
  _DeleteDeadline deadline,
  _DeleteProgress progress,
) async {
  final nonDirectories = <_PlannedPath>[];
  final directories = <_PlannedPath>[_PlannedPath(root.path, 0)];
  final iterator = StreamIterator<FileSystemEntity>(
    root.list(recursive: true, followLinks: false),
  );
  progress.plannedEntries = directories.length;

  try {
    while (await iterator.moveNext().timeout(deadline.nextListingTimeout())) {
      final entity = iterator.current;
      final entityPath = p.normalize(p.absolute(entity.path));
      if (!isPathWithinOrEqual(root.path, entityPath) ||
          p.equals(root.path, entityPath)) {
        throw BoundedDeleteException(
          reason: BoundedDeleteFailureReason.invalidTarget,
          message: '目录扫描返回了删除目标之外的路径。',
          path: entityPath,
          deletedEntries: 0,
          plannedEntries: nonDirectories.length + directories.length,
        );
      }
      if (nonDirectories.length + directories.length >= policy.maxEntries) {
        throw BoundedDeleteException(
          reason: BoundedDeleteFailureReason.entryLimitExceeded,
          message: '删除目标超过条目数量上限。',
          path: root.path,
          deletedEntries: 0,
          plannedEntries: nonDirectories.length + directories.length,
        );
      }

      final relativePath = p.relative(entityPath, from: root.path);
      final depth = p.split(relativePath).length;
      if (depth > policy.maxDepth) {
        throw BoundedDeleteException(
          reason: BoundedDeleteFailureReason.depthLimitExceeded,
          message: '删除目标超过目录深度上限。',
          path: entityPath,
          deletedEntries: 0,
          plannedEntries: nonDirectories.length + directories.length,
        );
      }
      final planned = _PlannedPath(entityPath, depth);
      if (entity is Directory) {
        directories.add(planned);
      } else {
        nonDirectories.add(planned);
      }
      progress.plannedEntries = nonDirectories.length + directories.length;
    }
  } finally {
    _cancelListing(iterator, policy.operationTimeout);
  }

  nonDirectories.sort((left, right) => left.path.compareTo(right.path));
  directories.sort((left, right) {
    final depthOrder = right.depth.compareTo(left.depth);
    return depthOrder != 0 ? depthOrder : left.path.compareTo(right.path);
  });
  return _DeletePlan(nonDirectories, directories);
}

void _cancelListing(
  StreamIterator<FileSystemEntity> iterator,
  Duration timeout,
) {
  unawaited(
    iterator
        .cancel()
        .timeout(timeout)
        .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
  );
}

Future<FileSystemEntityType> _entityType(
  String path,
  _DeleteDeadline deadline,
) {
  return FileSystemEntity.type(
    path,
    followLinks: false,
  ).timeout(deadline.nextOperationTimeout());
}

Future<String> _physicalDeletionTarget(
  String targetPath,
  FileSystemEntityType targetType,
  _DeleteDeadline deadline,
) async {
  if (targetType == FileSystemEntityType.directory) {
    return p.normalize(
      await Directory(
        targetPath,
      ).resolveSymbolicLinks().timeout(deadline.nextOperationTimeout()),
    );
  }
  final physicalParent = await Directory(
    p.dirname(targetPath),
  ).resolveSymbolicLinks().timeout(deadline.nextOperationTimeout());
  return p.normalize(p.join(physicalParent, p.basename(targetPath)));
}

Future<void> _deletePlannedPath(
  String path,
  _DeleteProgress progress,
  _DeleteDeadline deadline,
) async {
  progress.activePath = path;
  final type = await _entityType(path, deadline);
  switch (type) {
    case FileSystemEntityType.notFound:
      return;
    case FileSystemEntityType.directory:
      await Directory(path).delete().timeout(deadline.nextOperationTimeout());
      progress.directoryCount += 1;
    case FileSystemEntityType.link:
      await Link(path).delete().timeout(deadline.nextOperationTimeout());
      progress.linkCount += 1;
    case FileSystemEntityType.file:
    case FileSystemEntityType.pipe:
    case FileSystemEntityType.unixDomainSock:
      await File(path).delete().timeout(deadline.nextOperationTimeout());
      progress.fileCount += 1;
  }
  progress.deletedEntries += 1;
}

final class _PlannedPath {
  const _PlannedPath(this.path, this.depth);

  final String path;
  final int depth;
}

final class _DeletePlan {
  const _DeletePlan(this.nonDirectories, this.directories);

  final List<_PlannedPath> nonDirectories;
  final List<_PlannedPath> directories;

  int get entryCount => nonDirectories.length + directories.length;
}

final class _DeleteProgress {
  _DeleteProgress(this.activePath);

  String activePath;
  int plannedEntries = 0;
  int deletedEntries = 0;
  int fileCount = 0;
  int directoryCount = 0;
  int linkCount = 0;

  BoundedDeleteResult result() => BoundedDeleteResult(
    plannedEntries: plannedEntries,
    deletedEntries: deletedEntries,
    fileCount: fileCount,
    directoryCount: directoryCount,
    linkCount: linkCount,
    wasMissing: false,
  );
}

final class _DeleteDeadline {
  _DeleteDeadline(this.policy)
    : _deadline = MonotonicDeadline(
        policy.totalTimeout,
        timeoutMessage: '删除操作超过总时限。',
      );

  final BoundedDeletePolicy policy;
  final MonotonicDeadline _deadline;

  Duration nextOperationTimeout() => _nextTimeout(policy.operationTimeout);

  Duration nextListingTimeout() => _nextTimeout(policy.directoryIdleTimeout);

  Duration _nextTimeout(Duration maximum) {
    return _deadline.limit(maximum);
  }

  void stop() => _deadline.stop();
}
