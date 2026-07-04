import 'dart:async';
import 'dart:io';

import '../../app/support/safe_subprocess.dart';

/// Per-path write lock. All atomic writes that target the same absolute path
/// are serialized on a single [Future] chain to prevent two concurrent writers
/// from clobbering each other's `.tmp`/`.bak` files.
final Map<String, Future<void>> _writeLocks = <String, Future<void>>{};
const String _atomicTempSuffix = '.tmp';
const String _atomicBackupSuffix = '.bak';
const Duration _openDirectoryCommandTimeout = Duration(seconds: 6);
const String _openDirectoryProcessTag = 'atomic_file_ops';

/// Recovers a file from its atomic-write backup if the target is missing.
///
/// If the application was terminated between the "rename original → .bak" and
/// "rename .tmp → target" steps inside [writeFileAtomically], neither the
/// target file nor the .tmp file will exist, but the .bak file that holds the
/// previous content will still be present.  This function detects that state
/// and renames the .bak back to the target so that subsequent reads succeed.
///
/// Call this once for each critical file **before** reading it at startup.
/// It is safe to call even when no leftover artifacts exist.
Future<void> recoverAtomicWriteBackupIfNeeded(File targetFile) async {
  final tempFile = File('${targetFile.path}$_atomicTempSuffix');

  if (await targetFile.exists()) {
    // Target is intact — clean up any orphaned .tmp file.
    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } on FileSystemException {
        // Best-effort cleanup; ignore if the file cannot be deleted.
      }
    }
    return;
  }

  // Target is missing — try restoring from the .tmp file first (this
  // covers the case where the process crashed after writing the .tmp file
  // but before renaming it to the target).
  if (await tempFile.exists()) {
    try {
      await tempFile.rename(targetFile.path);
      return;
    } on FileSystemException {
      // .tmp rename failed — fall through to try the .bak file.
      try {
        await tempFile.delete();
      } on FileSystemException {
        // Best-effort cleanup.
      }
    }
  }

  // Restore from backup if available.
  final backupFile = File('${targetFile.path}$_atomicBackupSuffix');
  if (await backupFile.exists()) {
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
    () => _writeFileAtomicallyLocked(targetFile, content),
  );
}

/// Writes binary [bytes] to [targetFile] with the same lock/rename/rollback
/// behavior as [writeFileAtomically].
Future<void> writeFileBytesAtomically(File targetFile, List<int> bytes) {
  return _runWithAtomicWriteLock(
    targetFile,
    () => _writeFileBytesAtomicallyLocked(targetFile, bytes),
  );
}

Future<void> _runWithAtomicWriteLock(
  File targetFile,
  Future<void> Function() operation,
) {
  final key = targetFile.absolute.path;
  final previous = _writeLocks[key] ?? Future<void>.value();
  final current = previous.catchError((Object _, StackTrace _) {}).then((_) {
    return operation();
  });
  _writeLocks[key] = current;
  // Remove the lock once this write finishes (success or failure) and no
  // other caller queued behind it.
  current.whenComplete(() {
    if (identical(_writeLocks[key], current)) {
      _writeLocks.remove(key);
    }
  });
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

Future<void> _writeAtomicallyLocked(
  File targetFile,
  Future<void> Function(File tempFile) writeTempFile,
) async {
  // Ensure the parent directory exists before writing. Without this, writing
  // the `.tmp` file will fail on fresh installs or after the user deletes
  // storage directories.
  final parent = targetFile.parent;
  if (!await parent.exists()) {
    try {
      await parent.create(recursive: true);
    } on FileSystemException {
      // Fall through — the subsequent writeAsString will surface a precise
      // error if the directory is still missing.
    }
  }

  final tempFile = File('${targetFile.path}$_atomicTempSuffix');
  final backupFile = File('${targetFile.path}$_atomicBackupSuffix');

  if (await tempFile.exists()) {
    await tempFile.delete();
  }
  await writeTempFile(tempFile);

  var movedExistingFile = false;
  try {
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
  } on FileSystemException {
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
