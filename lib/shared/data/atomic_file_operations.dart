import 'dart:io';

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
  final tempFile = File('${targetFile.path}.tmp');

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
  final backupFile = File('${targetFile.path}.bak');
  if (await backupFile.exists()) {
    await backupFile.rename(targetFile.path);
  }
}

/// Writes [content] to [targetFile] atomically by first writing to a temporary
/// file, then renaming. If renaming fails, the original file is restored from
/// a backup.
///
/// This avoids data loss when the process crashes mid-write.
Future<void> writeFileAtomically(File targetFile, String content) async {
  final tempFile = File('${targetFile.path}.tmp');
  final backupFile = File('${targetFile.path}.bak');

  if (await tempFile.exists()) {
    await tempFile.delete();
  }
  await tempFile.writeAsString(content, flush: true);

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
      await backupFile.rename(targetFile.path);
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

  late final ProcessResult result;
  try {
    if (Platform.isMacOS) {
      result = await Process.run('open', <String>[directory.path]);
    } else if (Platform.isWindows) {
      result = await Process.run('explorer', <String>[directory.path]);
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', <String>[directory.path]);
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
  } on ProcessException catch (error) {
    throw FileSystemException(error.message);
  }

  // Windows explorer.exe always returns exit code 1 even on success,
  // so skip the exit code check for it.
  if (result.exitCode != 0 && !Platform.isWindows) {
    final message = '${result.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty ? 'Unable to open directory.' : message,
    );
  }
}
