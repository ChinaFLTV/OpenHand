import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'async_concurrency.dart';
import 'path_safety.dart';

const Duration _physicalPathMetadataTimeout = Duration(seconds: 3);
const Duration _physicalPathResolutionTimeout = Duration(seconds: 10);

/// 仅当 [candidate] 的物理路径等于 [parent] 或位于其内部时返回 `true`。
///
/// 父路径必须是既有目录；两侧既有符号链接都会被解析。候选路径缺失时解析最近的
/// 既有祖先并拼回剩余片段，避免通过符号链接目录逃逸。路径无效、悬空、不可访问、
/// 层级过深或文件系统操作超时时均按不安全处理。
Future<bool> isPhysicalPathWithinOrEqual(
  String parent,
  String candidate,
) async {
  final rawParent = parent.trim();
  final rawCandidate = candidate.trim();
  if (rawParent.isEmpty ||
      rawCandidate.isEmpty ||
      rawParent.contains('\u0000') ||
      rawCandidate.contains('\u0000')) {
    return false;
  }

  final deadline = MonotonicDeadline(
    _physicalPathResolutionTimeout,
    timeoutMessage: '解析物理路径超过总时限。',
  );
  Duration nextTimeout() => deadline.limit(_physicalPathMetadataTimeout);
  try {
    final normalizedParent = p.normalize(p.absolute(rawParent));
    final parentType = await FileSystemEntity.type(
      normalizedParent,
    ).timeout(nextTimeout());
    if (parentType != FileSystemEntityType.directory) return false;
    final physicalParent = p.normalize(
      await Directory(
        normalizedParent,
      ).resolveSymbolicLinks().timeout(nextTimeout()),
    );
    final physicalCandidate = await _resolvePhysicalPathAllowingMissing(
      p.normalize(p.absolute(rawCandidate)),
      nextTimeout: nextTimeout,
    );
    return physicalCandidate != null &&
        isPathWithinOrEqual(physicalParent, physicalCandidate);
  } on FileSystemException {
    return false;
  } on TimeoutException {
    return false;
  } on ArgumentError {
    return false;
  } finally {
    deadline.stop();
  }
}

Future<String?> _resolvePhysicalPathAllowingMissing(
  String absolutePath, {
  required Duration Function() nextTimeout,
}) async {
  final missingSegments = <String>[];
  var current = absolutePath;

  for (var depth = 0; depth < kOpenHandMaxAncestorDirectoryDepth; depth += 1) {
    final type = await FileSystemEntity.type(
      current,
      followLinks: false,
    ).timeout(nextTimeout());
    if (type != FileSystemEntityType.notFound) {
      final FileSystemEntity entity = switch (type) {
        FileSystemEntityType.directory => Directory(current),
        FileSystemEntityType.link => Link(current),
        _ => File(current),
      };
      final resolved = await entity.resolveSymbolicLinks().timeout(
        nextTimeout(),
      );
      return p.normalize(
        missingSegments.isEmpty
            ? resolved
            : p.joinAll(<String>[resolved, ...missingSegments.reversed]),
      );
    }

    final parent = p.dirname(current);
    if (parent == current) return null;
    missingSegments.add(p.basename(current));
    current = parent;
  }
  return null;
}
