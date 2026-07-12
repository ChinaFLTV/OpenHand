import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../app/support/safe_subprocess.dart';
import '../util/bounded_file_io.dart';

/// Process-local queue for each normalized target. A separate OS file lock is
/// acquired inside the queue so independent app instances cannot clobber the
/// shared `.bak` file or interleave their publish/rollback sequence.
final Map<String, Future<void>> _writeLocks = <String, Future<void>>{};
const String _atomicTempSuffix = '.tmp';
const String _atomicBackupSuffix = '.bak';
const String _atomicWritingMarker = '.writing.';
const String _atomicProcessLockDirectoryName = 'openhand-atomic-locks-v1';
const String _atomicProcessLockSuffix = '.lock';
const Duration _atomicStaleArtifactAge = Duration(minutes: 10);
const Duration _atomicIoIdleTimeout = Duration(seconds: 30);
const Duration _atomicProcessLockTimeout = Duration(seconds: 30);
const Duration _atomicProcessLockAttemptTimeout = Duration(seconds: 2);
const Duration _atomicProcessLockRetryDelay = Duration(milliseconds: 25);
const Duration _atomicOperationTotalTimeout = Duration(minutes: 10);
const Duration _atomicCleanupTimeout = Duration(seconds: 2);
const int _atomicIoChunkBytes = 64 * 1024;
const int _atomicTextChunkCodeUnits = 64 * 1024;
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
/// targeting the same normalized path are serialized in-process and across app
/// instances so two writers cannot race on the `.tmp`/`.bak` files.
Future<void> writeFileAtomically(File targetFile, String content) {
  return _runWithAtomicWriteLock(
    targetFile,
    (targetFile) => _writeFileAtomicallyLocked(targetFile, content),
  );
}

/// Writes binary [bytes] to [targetFile] with the same lock/rename/rollback
/// behavior as [writeFileAtomically].
Future<void> writeFileBytesAtomically(File targetFile, List<int> bytes) {
  // Capture caller-owned mutable data before the first asynchronous boundary.
  // Otherwise an in-flight mutation can silently publish a mixed payload even
  // when the list length remains unchanged.
  final snapshot = Uint8List.fromList(bytes);
  return _runWithAtomicWriteLock(
    targetFile,
    (targetFile) => _writeFileBytesAtomicallyLocked(targetFile, snapshot),
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
  final normalizedTargetFile = File(p.normalize(p.absolute(targetFile.path)));
  final key = normalizedTargetFile.path;
  final previous = _writeLocks[key] ?? Future<void>.value();
  final current = previous.catchError((Object _, StackTrace _) {}).then<void>((
    _,
  ) async {
    final processLock = await _acquireAtomicProcessLock(normalizedTargetFile);
    try {
      await operation(normalizedTargetFile);
    } finally {
      await processLock.release();
    }
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

class _AtomicProcessLockLease {
  _AtomicProcessLockLease(this._file);

  final RandomAccessFile _file;
  bool _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    final unlockFuture = _file.unlock();
    try {
      await unlockFuture.timeout(_atomicCleanupTimeout);
    } catch (_) {
      unawaited(
        unlockFuture
            .then<void>((_) {}, onError: (Object _, StackTrace _) {})
            .whenComplete(() => _closeAtomicProcessLockFile(_file)),
      );
      return;
    }
    await _closeAtomicProcessLockFile(_file);
  }
}

Future<_AtomicProcessLockLease> _acquireAtomicProcessLock(
  File targetFile,
) async {
  final lockFile = await _atomicProcessLockFile(targetFile);
  final handle = await _openAtomicFile(
    lockFile,
    FileMode.append,
    () => _atomicProcessLockTimeout,
  );
  final stopwatch = Stopwatch()..start();
  while (true) {
    final remainingMicroseconds =
        _atomicProcessLockTimeout.inMicroseconds -
        stopwatch.elapsedMicroseconds;
    if (remainingMicroseconds <= 0) {
      await _closeAtomicProcessLockFile(handle);
      throw _atomicProcessLockTimeoutException();
    }
    final remaining = Duration(microseconds: remainingMicroseconds);
    // The default is a non-blocking exclusive attempt. Retrying it ourselves
    // keeps cancellation and the total wait budget under application control.
    final lockFuture = handle.lock();
    try {
      await lockFuture.timeout(
        _shorterAtomicDuration(_atomicProcessLockAttemptTimeout, remaining),
        onTimeout: () => throw _atomicProcessLockTimeoutException(),
      );
      stopwatch.stop();
      return _AtomicProcessLockLease(handle);
    } on FileSystemException catch (error) {
      if (!_isAtomicProcessLockContention(error)) {
        stopwatch.stop();
        await _closeAtomicProcessLockFile(handle);
        rethrow;
      }
      final retryBudget =
          _atomicProcessLockTimeout.inMicroseconds -
          stopwatch.elapsedMicroseconds;
      if (retryBudget <= 0) {
        stopwatch.stop();
        await _closeAtomicProcessLockFile(handle);
        throw _atomicProcessLockTimeoutException();
      }
      await Future<void>.delayed(
        _shorterAtomicDuration(
          _atomicProcessLockRetryDelay,
          Duration(microseconds: retryBudget),
        ),
      );
    } on TimeoutException {
      stopwatch.stop();
      unawaited(_releaseLateAtomicProcessLock(handle, lockFuture));
      rethrow;
    } catch (_) {
      stopwatch.stop();
      await _closeAtomicProcessLockFile(handle);
      rethrow;
    }
  }
}

TimeoutException _atomicProcessLockTimeoutException() {
  return TimeoutException(
    'Waiting for another atomic writer timed out.',
    _atomicProcessLockTimeout,
  );
}

bool _isAtomicProcessLockContention(FileSystemException error) {
  final code = error.osError?.errorCode;
  if (Platform.isWindows) {
    return code == 33 || code == 36;
  }
  return code == 11 || code == 13 || code == 35;
}

Future<void> _releaseLateAtomicProcessLock(
  RandomAccessFile handle,
  Future<RandomAccessFile> lockFuture,
) async {
  try {
    await lockFuture;
    try {
      await handle.unlock();
    } catch (_) {
      // Closing the descriptor below also releases an acquired lock.
    }
  } catch (_) {
    // The descriptor still needs closing after a late lock failure.
  }
  await _closeAtomicProcessLockFile(handle);
}

Future<File> _atomicProcessLockFile(File targetFile) async {
  final directory = Directory(
    p.join(Directory.systemTemp.path, _atomicProcessLockDirectoryName),
  );
  if (!await directory.exists().timeout(_atomicProcessLockTimeout)) {
    await directory.create(recursive: true).timeout(_atomicProcessLockTimeout);
  }
  var identity = p.normalize(p.absolute(targetFile.path));
  if (Platform.isWindows) identity = identity.toLowerCase();
  final digest = sha256.convert(utf8.encode(identity));
  return File(p.join(directory.path, '$digest$_atomicProcessLockSuffix'));
}

Future<void> _closeAtomicProcessLockFile(RandomAccessFile file) async {
  final closeFuture = file.close();
  try {
    await closeFuture.timeout(_atomicCleanupTimeout);
  } catch (_) {
    unawaited(closeFuture.catchError((Object _, StackTrace _) {}));
  }
}

Future<void> _writeFileAtomicallyLocked(File targetFile, String content) async {
  await _writeAtomicallyLocked(
    targetFile,
    (tempFile, remainingBudget) => _writeAtomicTempFile(
      tempFile,
      remainingBudget,
      (output, nextOperationTimeout) async {
        var offset = 0;
        while (offset < content.length) {
          var end = offset + _atomicTextChunkCodeUnits;
          if (end >= content.length) {
            end = content.length;
          } else if (_isHighSurrogate(content.codeUnitAt(end - 1)) &&
              _isLowSurrogate(content.codeUnitAt(end))) {
            end += 1;
          }
          final chunk = utf8.encode(content.substring(offset, end));
          await output.run(
            (file) => file.writeFrom(chunk),
            timeout: nextOperationTimeout(),
          );
          offset = end;
        }
      },
    ),
  );
}

Future<void> _writeFileBytesAtomicallyLocked(
  File targetFile,
  Uint8List bytes,
) async {
  await _writeAtomicallyLocked(
    targetFile,
    (tempFile, remainingBudget) => _writeAtomicTempFile(
      tempFile,
      remainingBudget,
      (output, nextOperationTimeout) async {
        final length = bytes.length;
        var offset = 0;
        while (offset < length) {
          final end = offset + _atomicIoChunkBytes < length
              ? offset + _atomicIoChunkBytes
              : length;
          await output.run(
            (file) => file.writeFrom(bytes, offset, end),
            timeout: nextOperationTimeout(),
          );
          offset = end;
        }
      },
    ),
  );
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

Future<void> _writeAtomicTempFile(
  File tempFile,
  Duration Function() remainingBudget,
  Future<void> Function(
    BoundedRandomAccessFileLease output,
    Duration Function() nextOperationTimeout,
  )
  writeChunks,
) async {
  Duration nextOperationTimeout() =>
      _shorterAtomicDuration(_atomicIoIdleTimeout, remainingBudget());

  BoundedRandomAccessFileLease? output;
  try {
    final openedOutput = BoundedRandomAccessFileLease(
      await _openAtomicFile(
        tempFile,
        FileMode.writeOnly,
        nextOperationTimeout,
        deleteIfOpenCompletesLate: true,
      ),
    );
    output = openedOutput;
    await writeChunks(openedOutput, nextOperationTimeout);
    await openedOutput.run(
      (file) => file.flush(),
      timeout: nextOperationTimeout(),
    );
    await openedOutput.close(timeout: nextOperationTimeout());
    output = null;
  } finally {
    await output?.cleanup();
  }
}

Future<void> _copyFileAtomicallyLocked(
  File sourceFile,
  File targetFile, {
  required int maxBytes,
}) async {
  await _writeAtomicallyLocked(targetFile, (tempFile, remainingBudget) async {
    Duration nextOperationTimeout() =>
        _shorterAtomicDuration(_atomicIoIdleTimeout, remainingBudget());

    final preflightStat = await sourceFile.stat().timeout(
      nextOperationTimeout(),
    );
    if (!isRegularFileStat(preflightStat)) {
      throw FileSystemException(
        'Source path is not a regular file.',
        sourceFile.path,
      );
    }

    BoundedRandomAccessFileLease? input;
    BoundedRandomAccessFileLease? output;
    try {
      final openedInput = BoundedRandomAccessFileLease(
        await _openAtomicFile(sourceFile, FileMode.read, nextOperationTimeout),
      );
      input = openedInput;
      final initialStat = await sourceFile.stat().timeout(
        nextOperationTimeout(),
      );
      if (!isRegularFileStat(initialStat) ||
          initialStat.size != preflightStat.size ||
          initialStat.modified != preflightStat.modified ||
          initialStat.changed != preflightStat.changed) {
        throw FileSystemException(
          'Source path changed before it was opened.',
          sourceFile.path,
        );
      }
      final sourceLength = await openedInput.run(
        (file) => file.length(),
        timeout: nextOperationTimeout(),
      );
      if (sourceLength < 0 || sourceLength > maxBytes) {
        throw FileSystemException(
          'Source file exceeded the $maxBytes byte copy limit.',
          sourceFile.path,
        );
      }
      if (sourceLength != initialStat.size) {
        throw FileSystemException(
          'Source path changed before it was opened.',
          sourceFile.path,
        );
      }

      final openedOutput = BoundedRandomAccessFileLease(
        await _openAtomicFile(
          tempFile,
          FileMode.writeOnly,
          nextOperationTimeout,
          deleteIfOpenCompletesLate: true,
        ),
      );
      output = openedOutput;
      var remaining = sourceLength;
      while (remaining > 0) {
        final chunk = await openedInput.run(
          (file) => file.read(
            remaining < _atomicIoChunkBytes ? remaining : _atomicIoChunkBytes,
          ),
          timeout: nextOperationTimeout(),
        );
        if (chunk.isEmpty) {
          throw FileSystemException(
            'Source file changed while it was being copied.',
            sourceFile.path,
          );
        }
        await openedOutput.run(
          (file) => file.writeFrom(chunk),
          timeout: nextOperationTimeout(),
        );
        remaining -= chunk.length;
      }

      final finalLength = await openedInput.run(
        (file) => file.length(),
        timeout: nextOperationTimeout(),
      );
      final finalStat = await sourceFile.stat().timeout(nextOperationTimeout());
      if (finalLength != sourceLength ||
          !isRegularFileStat(finalStat) ||
          finalStat.size != sourceLength ||
          finalStat.modified != initialStat.modified ||
          finalStat.changed != initialStat.changed) {
        throw FileSystemException(
          'Source file changed while it was being copied.',
          sourceFile.path,
        );
      }
      await openedOutput.run(
        (file) => file.flush(),
        timeout: nextOperationTimeout(),
      );
      await openedOutput.close(timeout: nextOperationTimeout());
      output = null;
      await openedInput.close(timeout: nextOperationTimeout());
      input = null;
    } finally {
      await Future.wait<void>(<Future<void>>[
        if (output != null) output.cleanup(),
        if (input != null) input.cleanup(),
      ]);
    }
  });
}

Future<RandomAccessFile> _openAtomicFile(
  File file,
  FileMode mode,
  Duration Function() remainingBudget, {
  bool deleteIfOpenCompletesLate = false,
}) async {
  final timeout = remainingBudget();
  final openFuture = file.open(mode: mode);
  try {
    return await openFuture.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'Opening an atomic file operation timed out.',
        timeout,
      ),
    );
  } on TimeoutException {
    unawaited(
      _closeLateAtomicFile(
        openFuture,
        incompleteFile: deleteIfOpenCompletesLate ? file : null,
      ),
    );
    rethrow;
  }
}

Future<void> _closeLateAtomicFile(
  Future<RandomAccessFile> openFuture, {
  File? incompleteFile,
}) async {
  try {
    final file = await openFuture;
    // This runs outside the caller's critical path. Await the real close so a
    // synthetic timeout cannot leave a newly-created working file behind.
    await file.close();
  } catch (_) {
    // The primary operation has already timed out; cleanup remains best effort.
  }
  if (incompleteFile != null) {
    try {
      if (await incompleteFile.exists()) {
        await incompleteFile.delete();
      }
    } on FileSystemException {
      // Stale-artifact cleanup remains the final fallback.
    }
  }
}

Duration _shorterAtomicDuration(Duration first, Duration second) {
  return first < second ? first : second;
}

Future<void> _writeAtomicallyLocked(
  File targetFile,
  Future<void> Function(File tempFile, Duration Function() remainingBudget)
  writeTempFile,
) async {
  final stopwatch = Stopwatch()..start();
  Duration remainingBudget() {
    final remaining =
        _atomicOperationTotalTimeout.inMicroseconds -
        stopwatch.elapsedMicroseconds;
    if (remaining <= 0) {
      throw TimeoutException(
        'Atomic file operation exceeded its time limit.',
        _atomicOperationTotalTimeout,
      );
    }
    return Duration(microseconds: remaining);
  }

  final tempFiles = _newAtomicTempFiles(targetFile);
  final workingFile = tempFiles.working;
  final tempFile = tempFiles.ready;
  final backupFile = _atomicBackupFile(targetFile);
  var movedExistingFile = false;
  try {
    await _ensureAtomicParentDirectory(targetFile).timeout(remainingBudget());
    await writeTempFile(workingFile, remainingBudget);
    if (!await workingFile.exists().timeout(remainingBudget())) {
      throw FileSystemException(
        'Atomic working file disappeared before it was finalized.',
        workingFile.path,
      );
    }
    // File-system mutations are not cancellable. Await the three atomic
    // switch operations to completion so a late rename cannot race rollback
    // or a subsequent writer after a synthetic Future.timeout failure.
    await workingFile.rename(tempFile.path);
    if (!await tempFile.exists().timeout(remainingBudget())) {
      throw FileSystemException(
        'Atomic temp file disappeared before rename.',
        tempFile.path,
      );
    }
    if (await backupFile.exists().timeout(remainingBudget())) {
      await backupFile.delete();
    }
    if (await targetFile.exists().timeout(remainingBudget())) {
      await targetFile.rename(backupFile.path);
      movedExistingFile = true;
    }
    await tempFile.rename(targetFile.path);
    try {
      if (await backupFile.exists().timeout(remainingBudget())) {
        final discardFile = _newAtomicDiscardFile(targetFile);
        await backupFile.rename(discardFile.path);
        try {
          await discardFile.delete().timeout(_atomicCleanupTimeout);
        } catch (_) {
          // The unique discard path cannot collide with a later writer and is
          // collected with other incomplete temp artifacts once it is stale.
        }
      }
    } catch (_) {
      // The new target is already published; backup cleanup is best effort.
    }
  } catch (_) {
    // Best-effort cleanup: remove temp and restore backup. Errors during
    // cleanup must not prevent the backup restoration or shadow the
    // original exception.
    for (final artifact in <File>[workingFile, tempFile]) {
      try {
        if (await artifact.exists().timeout(_atomicCleanupTimeout)) {
          await artifact.delete().timeout(_atomicCleanupTimeout);
        }
      } catch (_) {
        // Ignore cleanup failure. Incomplete working files are never selected
        // by recovery; a complete ready file remains a safe recovery option.
      }
    }
    var backupExists = false;
    if (movedExistingFile) {
      try {
        backupExists = await backupFile.exists();
      } catch (_) {
        // Keep the primary failure when metadata cannot be inspected.
      }
    }
    if (backupExists) {
      try {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
      } catch (_) {
        // Ignore — proceed with restoration attempt anyway.
      }
      try {
        await backupFile.rename(targetFile.path);
      } catch (_) {
        // If even the rollback fails, fall through and rethrow the original
        // exception so the caller can surface the problem.
      }
    }
    rethrow;
  } finally {
    stopwatch.stop();
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

({File working, File ready}) _newAtomicTempFiles(File targetFile) {
  final serial = _atomicTempSerial++;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final suffix = '$pid.$stamp.$serial';
  final base = '${targetFile.path}$_atomicTempSuffix';
  return (
    working: File('$base$_atomicWritingMarker$suffix'),
    ready: File('$base.$suffix'),
  );
}

File _newAtomicDiscardFile(File targetFile) {
  final serial = _atomicTempSerial++;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return File(
    '${targetFile.path}$_atomicTempSuffix$_atomicWritingMarker'
    'discard.$pid.$stamp.$serial',
  );
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
  for (final file in await _atomicTempArtifacts(
    targetFile,
    includeIncomplete: true,
  )) {
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

Future<List<File>> _atomicTempArtifacts(
  File targetFile, {
  bool includeIncomplete = false,
}) async {
  final parent = targetFile.parent;
  if (!await parent.exists()) {
    return const <File>[];
  }
  final legacyTempPath = '${targetFile.path}$_atomicTempSuffix';
  final uniqueTempPrefix = '$legacyTempPath.';
  final incompleteTempPrefix = '$legacyTempPath$_atomicWritingMarker';
  final artifacts = <File>[];
  try {
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (entity.path == legacyTempPath ||
          entity.path.startsWith(uniqueTempPrefix)) {
        if (!includeIncomplete &&
            entity.path.startsWith(incompleteTempPrefix)) {
          continue;
        }
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
