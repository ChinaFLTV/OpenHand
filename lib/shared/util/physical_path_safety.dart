import 'dart:io';

import 'package:path/path.dart' as p;

import 'path_safety.dart';

/// Returns true only when the physical target of [candidate] is [parent] or a
/// descendant of it.
///
/// The parent must be an existing directory. Existing symlinks are resolved on
/// both sides. A missing candidate is checked by resolving its closest existing
/// ancestor and appending the remaining normalized segments, which keeps new
/// files beneath symlinked directories from escaping the parent. Any malformed,
/// dangling, inaccessible, or excessively deep path fails closed.
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

  try {
    final normalizedParent = p.normalize(p.absolute(rawParent));
    final parentType = await FileSystemEntity.type(normalizedParent);
    if (parentType != FileSystemEntityType.directory) return false;
    final physicalParent = p.normalize(
      await Directory(normalizedParent).resolveSymbolicLinks(),
    );
    final physicalCandidate = await _resolvePhysicalPathAllowingMissing(
      p.normalize(p.absolute(rawCandidate)),
    );
    return physicalCandidate != null &&
        isPathWithinOrEqual(physicalParent, physicalCandidate);
  } on FileSystemException {
    return false;
  } on ArgumentError {
    return false;
  }
}

Future<String?> _resolvePhysicalPathAllowingMissing(String absolutePath) async {
  final missingSegments = <String>[];
  var current = absolutePath;

  for (var depth = 0; depth < kOpenHandMaxAncestorDirectoryDepth; depth += 1) {
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      final FileSystemEntity entity = switch (type) {
        FileSystemEntityType.directory => Directory(current),
        FileSystemEntityType.link => Link(current),
        _ => File(current),
      };
      final resolved = await entity.resolveSymbolicLinks();
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
