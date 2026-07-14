import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'bounded_file_io.dart';

const int kNodePackageManifestMaxBytes = 2 * 1024 * 1024;
const Duration kNodePackageManifestIoTimeout = Duration(seconds: 3);

/// Resolves the first executable declared by a Node package without allowing
/// an absolute path or `..` segment to escape the package directory.
Future<String?> resolveNodePackageBinEntry(
  String packageDirectoryPath, {
  int maxManifestBytes = kNodePackageManifestMaxBytes,
  Duration idleTimeout = kNodePackageManifestIoTimeout,
  Duration totalTimeout = defaultBoundedFileReadTotalTimeout,
}) async {
  if (idleTimeout <= Duration.zero) {
    throw ArgumentError.value(idleTimeout, 'idleTimeout', 'Must be positive.');
  }
  if (totalTimeout <= Duration.zero) {
    throw ArgumentError.value(
      totalTimeout,
      'totalTimeout',
      'Must be positive.',
    );
  }
  final stopwatch = Stopwatch()..start();
  Duration remainingBudget() {
    final microseconds =
        totalTimeout.inMicroseconds - stopwatch.elapsedMicroseconds;
    if (microseconds <= 0) {
      throw TimeoutException(
        'Node package manifest resolution exceeded its time limit.',
        totalTimeout,
      );
    }
    return Duration(microseconds: microseconds);
  }

  Duration nextOperationTimeout() {
    final remaining = remainingBudget();
    return remaining < idleTimeout ? remaining : idleTimeout;
  }

  try {
    final packageRoot = p.normalize(p.absolute(packageDirectoryPath));
    final manifest = File(p.join(packageRoot, 'package.json'));
    final manifestType = await FileSystemEntity.type(
      manifest.path,
      followLinks: false,
    ).timeout(nextOperationTimeout());
    if (manifestType != FileSystemEntityType.file) return null;
    final decoded = jsonDecode(
      await readBoundedFileString(
        manifest,
        maxBytes: maxManifestBytes,
        idleTimeout: nextOperationTimeout(),
        totalTimeout: remainingBudget(),
      ),
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
    final entryType = await FileSystemEntity.type(
      resolved,
      followLinks: false,
    ).timeout(nextOperationTimeout());
    return entryType == FileSystemEntityType.file ? resolved : null;
  } on TimeoutException {
    return null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on BoundedFileReadException {
    return null;
  } finally {
    stopwatch.stop();
  }
}
