import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'bounded_file_io.dart';

const int kNodePackageManifestMaxBytes = 2 * 1024 * 1024;

/// Resolves the first executable declared by a Node package without allowing
/// an absolute path or `..` segment to escape the package directory.
String? resolveNodePackageBinEntry(
  String packageDirectoryPath, {
  int maxManifestBytes = kNodePackageManifestMaxBytes,
}) {
  try {
    final packageRoot = p.normalize(p.absolute(packageDirectoryPath));
    final manifest = File(p.join(packageRoot, 'package.json'));
    if (!manifest.existsSync()) return null;
    final decoded = jsonDecode(
      readBoundedFileStringSync(manifest, maxBytes: maxManifestBytes),
    );
    if (decoded is! Map) return null;

    final bin = decoded['bin'];
    final Object? rawEntry = switch (bin) {
      String() => bin,
      Map() when bin.isNotEmpty => bin.values.first,
      _ => null,
    };
    if (rawEntry is! String) return null;
    final relativeEntry = rawEntry.trim();
    if (relativeEntry.isEmpty || p.isAbsolute(relativeEntry)) return null;

    final resolved = p.normalize(p.join(packageRoot, relativeEntry));
    if (!p.isWithin(packageRoot, resolved)) return null;
    return FileSystemEntity.typeSync(resolved) == FileSystemEntityType.file
        ? resolved
        : null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on BoundedFileReadException {
    return null;
  }
}
