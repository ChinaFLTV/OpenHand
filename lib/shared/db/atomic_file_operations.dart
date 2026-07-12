import 'dart:async';
import 'dart:io';

import '../../app/support/safe_subprocess.dart';
import '../net/http_response_utils.dart';

/// Per-path write lock. All atomic writes that target the same absolute path
/// are serialized on a single [Future] chain to prevent two concurrent writers
/// from clobbering each other's `.tmp`/`.bak` files.
final Map<String, Future<void>> _writeLocks = <String, Future<void>>{};
const String _atomicTempSuffix = '.tmp';
const String _atomicBackupSuffix = '.bak';
const Duration _atomicStaleArtifactAge = Duration(minutes: 10);
const Duration _atomicCopyIdleTimeout = Duration(seconds: 30);
const Duration _atomicCopyTotalTimeout = Duration(minutes: 10);
const Duration _atomicCopyCloseTimeout = Duration(seconds: 2);
const Duration _openDirectoryCommandTimeout = Duration(seconds: 6);
const String _openDirectoryProcessTag = 'atomic_file_ops';
int _atomicTempSerial = 0;

/// Recovers a file from its atomic-write backup if the target is missing.
///
/// If the application was terminated during [writeFileAtomically], the target
/// may be missing while a `.tmp`/`.tmp.*` file or `.bak` file is still present.
/// This function restores the newest temp file first, then falls back to the
/// backup that holds the previous content.
///
/// Call this once for each critical file **before** reading it at startup.
/// It is safe to call even when no leftover artifacts exist.
Future<void> recoverAtomicWriteBackupIfNeeded(File targetFile) {
  return _runWithAtomicWriteLock(
    targetFile,
    _recoverAtomicWriteBackupIfNeededLocked,
  );
}

Future<void> _recoverAtomicWriteBackupIfNeededLocked(File targetFile) async {
  final parent = targetFile.parent;
  if (!await parent.exists()) {
    return;
  }
  final backupFile = _atomicBackupFile(targetFile);
  if (await targetFile.exists()) {
    // Target is intact. Keep recent temp artifacts because another app
    // instance may still be finishing its rename; only remove stale leftovers.
    await _deleteStaleAtomicTempArtifacts(targetFile);
    if (await backupFile.exists()) {
      try {
        await backupFile.delete();
      } on FileSystemException {
        // Best-effort cleanup; ignore if the file cannot be deleted.
      }
    }
    return;
  }

  // Target is missing — try restoring from the newest temp file first. This
  // covers both legacy `.tmp` files and the unique `.tmp.*` files used by
  // current writers.
  final tempFile = await _newestAtomicTempArtifact(targetFile);
  if (tempFile != null && await tempFile.exists()) {
    try {
      await _ensureAtomicParentDirectory(targetFile);
      await tempFile.rename(targetFile.path);
      if (await backupFile.exists()) {
        try {
          await backupFile.delete();
        } on FileSystemException {
          // Best-effort cleanup.
        }
      }
      return;
    } on FileSystemException {
      // Temp restore failed — fall through to try the backup file.
    }
  }

  // Restore from backup if available.
  if (await backupFile.exists()) {
    await _ensureAtomicParentDirectory(targetFile);
    await backupFile.rename(targetFile.path);
  }
}

/// Writes [content] to [targetFile] atomically by first writing to a temporary
/// file, then renaming. If renaming fails, the original file is restored from
/// a backup.
///
/// This avoids data loss when the process crashes mid-write. Concurrent calls
/// targeting the same absolute path are serialized via a per-path lock so that
/// two writers cannot race on the `.tmp`/`.bak` files.
Future<void> writeFileAtomically(File targetFile, String content) {
  return _runWithAtomicWriteLock(
    targetFile,
    (targetFile) => _writeFileAtomicallyLocked(targetFile, content),
  );
}

/// Writes binary [bytes] to [targetFile] with the same lock/rename/rollback
/// behavior as [writeFileAtomically].
Future<void> writeFileBytesAtomically(File targetFile, List<int> bytes) {
  return _runWithAtomicWriteLock(
    targetFile,
    (targetFile) => _writeFileBytesAtomicallyLocked(targetFile, bytes),
  );
}

/// Copies [sourceFile] to [targetFile] without materializing the source in
/// memory, while preserving the same atomic rename and rollback guarantees as
/// the write helpers. [maxBytes] is enforced while streaming, so a source that
/// grows during copying cannot consume unbounded memory or disk space.
Future<void> copyFileAtomically(
  File sourceFile,
  File targetFile, {
  required int maxBytes,
}) {
  if (maxBytes < 1) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
  }
  return _runWithAtomicWriteLock(
    targetFile,
    (targetFile) => _copyFileAtomicallyLocked(
      sourceFile.absolute,
      targetFile,
      maxBytes: maxBytes,
    ),
  );
}

Future<void> _runWithAtomicWriteLock(
  File targetFile,
  Future<void> Function(File targetFile) operation,
) {
  final normalizedTargetFile = targetFile.absolute;
  final key = normalizedTargetFile.path;
  final previous = _writeLocks[key] ?? Future<void>.value();
  final current = previous.catchError((Object _, StackTrace _) {}).then((_) {
    return operation(normalizedTargetFile);
  });
  _writeLocks[key] = current;
  // Remove the lock once this write finishes (success or failure) and no
  // other caller queued behind it.
  void releaseLock() {
    if (identical(_writeLocks[key], current)) {
      _writeLocks.remove(key);
    }
  }

  unawaited(
    current.then<void>(
      (_) => releaseLock(),
      onError: (Object _, StackTrace _) => releaseLock(),
    ),
  );
  return current;
}

Future<void> _writeFileAtomicallyLocked(File targetFile, String content) async {
  await _writeAtomicallyLocked(
    targetFile,
    (tempFile) => tempFile.writeAsString(content, flush: true),
  );
}

Future<void> _writeFileBytesAtomicallyLocked(
  File targetFile,
  List<int> bytes,
) async {
  await _writeAtomicallyLocked(
    targetFile,
    (tempFile) => tempFile.writeAsBytes(bytes, flush: true),
  );
}

Future<void> _copyFileAtomicallyLocked(
  File sourceFile,
  File targetFile, {
  required int maxBytes,
}) async {
  await _writeAtomicallyLocked(targetFile, (tempFile) async {
    final stopwatch = Stopwatch()..start();
    Duration remainingBudget() {
      final remaining =
          _atomicCopyTotalTimeout.inMicroseconds -
          stopwatch.elapsedMicroseconds;
      if (remaining <= 0) {
        throw TimeoutException(
          'Atomic file copy exceeded its time limit.',
          _atomicCopyTotalTimeout,
        );
      }
      return Duration(microseconds: remaining);
    }

    final sourceLength = await sourceFile.length().timeout(remainingBudget());
    if (sourceLength > maxBytes) {
      throw FileSystemException(
        'Source file exceeded the $maxBytes byte copy limit.',
        sourceFile.path,
      );
    }

    RandomAccessFile? output;
    var operationFailed = false;
    try {
      final openedOutput = await tempFile
          .open(mode: FileMode.writeOnly)
          .timeout(remainingBudget());
      output = openedOutput;
      final streamBudget = remainingBudget();
      await writeBoundedByteStream(
        sourceFile.openRead(),
        writeChunk: openedOutput.writeFrom,
        maxBytes: maxBytes,
        idleTimeout: streamBudget < _atomicCopyIdleTimeout
            ? streamBudget
            : _atomicCopyIdleTimeout,
        totalTimeout: streamBudget,
      );
      await openedOutput.flush().timeout(remainingBudget());
    } on HttpException {
      operationFailed = true;
      throw FileSystemException(
        'Source file exceeded the $maxBytes byte copy limit.',
        sourceFile.path,
      );
    } catch (_) {
      operationFailed = true;
      rethrow;
    } finally {
      stopwatch.stop();
      final activeOutput = output;
      if (activeOutput != null) {
        try {
          await activeOutput.close().timeout(_atomicCopyCloseTimeout);
        } catch (_) {
          if (!operationFailed) rethrow;
        }
      }
    }
  });
}

Future<void> _writeAtomicallyLocked(
  File targetFile,
  Future<void> Function(File tempFile) writeTempFile,
) async {
  await _ensureAtomicParentDirectory(targetFile);

  final tempFile = _newAtomicTempFile(targetFile);
  final backupFile = _atomicBackupFile(targetFile);
  var movedExistingFile = false;
  try {
    await writeTempFile(tempFile);
    if (!await tempFile.exists()) {
      throw FileSystemException(
        'Atomic temp file disappeared before rename.',
        tempFile.path,
      );
    }
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    if (await targetFile.exists()) {
      await targetFile.rename(backupFile.path);
      movedExistingFile = true;
    }
    await tempFile.rename(targetFile.path);
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
  } catch (_) {
    // Best-effort cleanup: remove temp and restore backup. Errors during
    // cleanup must not prevent the backup restoration or shadow the
    // original exception.
    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } on FileSystemException {
      // Ignore cleanup failure.
    }
    if (movedExistingFile && await backupFile.exists()) {
      try {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
      } on FileSystemException {
        // Ignore — proceed with restoration attempt anyway.
      }
      try {
        await backupFile.rename(targetFile.path);
      } on FileSystemException {
        // If even the rollback fails, fall through and rethrow the original
        // exception so the caller can surface the problem.
      }
    }
    rethrow;
  }
}

Future<void> _ensureAtomicParentDirectory(File targetFile) async {
  final parent = targetFile.parent;
  if (!await parent.exists()) {
    try {
      await parent.create(recursive: true);
    } on FileSystemException {
      // Fall through — the subsequent file operation will surface a precise
      // error if the directory is still missing.
    }
  }
}

File _atomicBackupFile(File targetFile) {
  return File('${targetFile.path}$_atomicBackupSuffix');
}

File _newAtomicTempFile(File targetFile) {
  final serial = _atomicTempSerial++;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return File('${targetFile.path}$_atomicTempSuffix.$pid.$stamp.$serial');
}

Future<File?> _newestAtomicTempArtifact(File targetFile) async {
  final artifacts = await _atomicTempArtifacts(targetFile);
  if (artifacts.isEmpty) {
    return null;
  }
  final stamped = <({File file, DateTime modified})>[];
  for (final file in artifacts) {
    try {
      stamped.add((file: file, modified: (await file.stat()).modified));
    } on FileSystemException {
      // Ignore files that disappeared while listing.
    }
  }
  if (stamped.isEmpty) {
    return null;
  }
  stamped.sort((a, b) => b.modified.compareTo(a.modified));
  return stamped.first.file;
}

Future<void> _deleteStaleAtomicTempArtifacts(File targetFile) async {
  final cutoff = DateTime.now().subtract(_atomicStaleArtifactAge);
  for (final file in await _atomicTempArtifacts(targetFile)) {
    try {
      final stat = await file.stat();
      if (stat.modified.isAfter(cutoff)) {
        continue;
      }
      await file.delete();
    } on FileSystemException {
      // Best-effort cleanup.
    }
  }
}

Future<List<File>> _atomicTempArtifacts(File targetFile) async {
  final parent = targetFile.parent;
  if (!await parent.exists()) {
    return const <File>[];
  }
  final legacyTempPath = '${targetFile.path}$_atomicTempSuffix';
  final uniqueTempPrefix = '$legacyTempPath.';
  final artifacts = <File>[];
  try {
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (entity.path == legacyTempPath ||
          entity.path.startsWith(uniqueTempPrefix)) {
        artifacts.add(entity);
      }
    }
  } on FileSystemException {
    return const <File>[];
  }
  return artifacts;
}

/// Opens a directory in the platform-native file manager.
///
/// Throws [FileSystemException] if the platform is unsupported or the
/// command fails.
Future<void> openDirectoryInFileManager(Directory directory) async {
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  final ProcessResult? result;
  try {
    if (Platform.isMacOS) {
      result = await runProcessWithTimeout(
        'open',
        <String>[directory.path],
        timeout: _openDirectoryCommandTimeout,
        tag: _openDirectoryProcessTag,
      );
    } else if (Platform.isWindows) {
      result = await runProcessWithTimeout(
        'explorer',
        <String>[directory.path],
        timeout: _openDirectoryCommandTimeout,
        tag: _openDirectoryProcessTag,
      );
    } else if (Platform.isLinux) {
      result = await runProcessWithTimeout(
        'xdg-open',
        <String>[directory.path],
        timeout: _openDirectoryCommandTimeout,
        tag: _openDirectoryProcessTag,
      );
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
  } on ProcessException catch (error) {
    throw FileSystemException(error.message);
  }

  // Windows explorer.exe always returns exit code 1 even on success,
  // so skip the exit code check for it.
  if (result == null) {
    throw const FileSystemException('Open command timed out.');
  }
  if (result.exitCode != 0 && !Platform.isWindows) {
    final message = '${result.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty ? 'Unable to open directory.' : message,
    );
  }
}
