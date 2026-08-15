import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'argument_guards.dart';
import 'async_concurrency.dart';
import 'bounded_file_io.dart';
import 'byte_size_format.dart';
import 'physical_path_safety.dart';

const int kNodePackageManifestMaxBytes = 2 * kBytesPerMiB;
const Duration kNodePackageManifestIoTimeout = Duration(seconds: 3);

/// 解析 Node 包声明的首个可执行文件，并阻止绝对路径或 `..` 逃逸包目录。
Future<String?> resolveNodePackageBinEntry(
  String packageDirectoryPath, {
  int maxManifestBytes = kNodePackageManifestMaxBytes,
  Duration idleTimeout = kNodePackageManifestIoTimeout,
  Duration totalTimeout = defaultBoundedFileReadTotalTimeout,
}) async {
  requirePositiveDuration(idleTimeout, 'idleTimeout');
  final deadline = MonotonicDeadline(
    totalTimeout,
    timeoutMessage: '解析 Node 包清单超过总时限。',
  );

  try {
    final packageRoot = p.normalize(p.absolute(packageDirectoryPath));
    final manifest = File(p.join(packageRoot, 'package.json'));
    final manifestType = await FileSystemEntity.type(
      manifest.path,
      followLinks: false,
    ).timeout(deadline.limit(idleTimeout));
    if (manifestType != FileSystemEntityType.file) return null;
    final decoded = jsonDecode(
      await readBoundedFileString(
        manifest,
        maxBytes: maxManifestBytes,
        idleTimeout: deadline.limit(idleTimeout),
        totalTimeout: deadline.remaining(),
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
    if (!p.isWithin(packageRoot, resolved) ||
        !await isPhysicalPathWithinOrEqual(
          packageRoot,
          resolved,
        ).timeout(deadline.limit(idleTimeout))) {
      return null;
    }
    final entryType = await FileSystemEntity.type(
      resolved,
      followLinks: false,
    ).timeout(deadline.limit(idleTimeout));
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
    deadline.stop();
  }
}
