import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'path_safety.dart';

typedef DirectoryCleanupErrorHandler =
    FutureOr<void> Function(
      Directory directory,
      Object error,
      StackTrace stack,
    );

Future<bool> isDirectoryEmpty(Directory directory) async {
  if (!await directory.exists()) return false;
  await for (final _ in directory.list(followLinks: false)) {
    return false;
  }
  return true;
}

Future<void> deleteEmptyAncestorDirectories({
  required Directory start,
  required Directory stopAt,
  DirectoryCleanupErrorHandler? onError,
  bool continuePastMissing = true,
}) async {
  final stopPath = p.normalize(stopAt.path);
  final startPath = p.normalize(start.path);
  if (p.equals(stopPath, startPath) ||
      !isPathWithinOrEqual(stopPath, startPath)) {
    return;
  }

  for (final currentPath in ancestorDirectoriesFrom(startPath)) {
    if (p.equals(stopPath, currentPath) ||
        !isPathWithinOrEqual(stopPath, currentPath)) {
      return;
    }
    final current = Directory(currentPath);
    if (!await current.exists()) {
      if (!continuePastMissing) return;
      continue;
    }
    if (!await isDirectoryEmpty(current)) return;
    try {
      await current.delete();
    } catch (error, stack) {
      if (onError == null) rethrow;
      await onError(current, error, stack);
      return;
    }
  }
}
