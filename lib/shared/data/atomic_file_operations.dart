import 'dart:io';

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
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    if (movedExistingFile && await backupFile.exists()) {
      if (await targetFile.exists()) {
        await targetFile.delete();
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
  if (Platform.isMacOS) {
    result = await Process.run('open', <String>[directory.path]);
  } else if (Platform.isWindows) {
    result = await Process.run('explorer', <String>[directory.path]);
  } else if (Platform.isLinux) {
    result = await Process.run('xdg-open', <String>[directory.path]);
  } else {
    throw const FileSystemException('Unsupported platform.');
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
