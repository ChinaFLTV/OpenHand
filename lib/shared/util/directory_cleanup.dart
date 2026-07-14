import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'bounded_directory_io.dart';
import 'path_safety.dart';

typedef DirectoryCleanupErrorHandler =
    FutureOr<void> Function(
      Directory directory,
      Object error,
      StackTrace stack,
    );

Future<bool> isDirectoryEmpty(Directory directory) async {
  try {
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    ).timeout(defaultBoundedDirectoryIdleTimeout);
    if (type != FileSystemEntityType.directory) return false;
  } on TimeoutException {
    return false;
  }
  final listing = await listDirectoryBounded(directory, maxEntries: 1);
  return !listing.truncated && listing.entries.isEmpty;
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
