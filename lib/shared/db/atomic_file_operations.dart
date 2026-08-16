import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../app/support/safe_subprocess.dart';
import '../util/argument_guards.dart';
import '../util/async_concurrency.dart';
import '../util/bounded_directory_io.dart';
import '../util/bounded_file_io.dart';
import '../util/byte_size_format.dart';
import '../util/duration_bounds.dart';
import '../util/serial_task_queue.dart';
import '../util/text_clip.dart';

/// 按规范化目标维护进程内队列，并在队列内获取系统文件锁，避免多个应用实例
/// 同时覆盖共享 `.bak` 文件或交错执行发布与回滚。
final KeyedSerialTaskQueue<String> _writeQueue = KeyedSerialTaskQueue<String>();
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
const Duration _atomicStreamWriteMaxTotalTimeout = Duration(minutes: 30);
const Duration _atomicCleanupTimeout = Duration(seconds: 2);
const Duration _atomicMetadataTimeout = Duration(seconds: 3);
const Duration _atomicRecoveryTotalTimeout = Duration(seconds: 30);
const Duration _atomicArtifactProcessingTimeout = Duration(seconds: 6);
const int _atomicIoChunkBytes = 64 * kBytesPerKiB;
const int _atomicTextChunkCodeUnits = 64 * kBytesPerKiB;
const int _atomicArtifactScanMaxEntries = 10000;
const Duration _atomicArtifactScanTimeout = Duration(seconds: 3);
const Duration _openDirectoryCommandTimeout = Duration(seconds: 6);
const String _openDirectoryProcessTag = 'atomic_file_ops';
const String _atomicModeProcessTag = 'atomic_file_ops.mode';
int _atomicTempSerial = 0;

/// 目标缺失时从原子写入残留中恢复文件。
///
/// 应用在 [writeFileAtomically] 期间终止后，目标可能缺失但仍保留 `.tmp`、
/// `.tmp.*` 或 `.bak`。本方法优先恢复最新的完整临时文件，再回退到旧内容备份。
///
/// 启动读取关键文件前调用一次；没有残留时可安全直接返回。
Future<void> recoverAtomicWriteBackupIfNeeded(File targetFile) {
  return _runWithAtomicWriteLock(
    targetFile,
    _recoverAtomicWriteBackupIfNeededLocked,
  );
}

Future<void> _recoverAtomicWriteBackupIfNeededLocked(File targetFile) async {
  final deadline = MonotonicDeadline(
    _atomicRecoveryTotalTimeout,
    timeoutMessage: '恢复原子文件超过总时限。',
  );
  Duration metadataTimeout() => deadline.limit(_atomicMetadataTimeout);
  try {
    final parent = targetFile.parent;
    if (!await parent.exists().timeout(metadataTimeout())) return;
    final backupFile = _atomicBackupFile(targetFile);
    if (await targetFile.exists().timeout(metadataTimeout())) {
      // 目标完整时保留其他实例可能仍在发布的近期临时文件，只清理过期残留。
      await _deleteStaleAtomicTempArtifacts(targetFile);
      if (await backupFile.exists().timeout(metadataTimeout())) {
        await _discardAtomicBackupQuietly(targetFile, backupFile);
      }
      return;
    }

    // 目标缺失时先恢复最新完整临时文件，失败后再尝试旧内容备份。
    final tempFile = await _newestAtomicTempArtifact(targetFile);
    if (tempFile != null &&
        await tempFile.exists().timeout(metadataTimeout())) {
      try {
        await _ensureAtomicParentDirectory(
          targetFile,
        ).timeout(deadline.remaining());
        await tempFile.rename(targetFile.path);
        if (await backupFile.exists().timeout(metadataTimeout())) {
          await _discardAtomicBackupQuietly(targetFile, backupFile);
        }
        return;
      } on FileSystemException {
        // 临时文件恢复失败后继续尝试备份。
      }
    }

    if (await backupFile.exists().timeout(metadataTimeout())) {
      await _ensureAtomicParentDirectory(
        targetFile,
      ).timeout(deadline.remaining());
      await backupFile.rename(targetFile.path);
    }
  } finally {
    deadline.stop();
  }
}

/// 先写入临时文件再重命名，以原子方式把 [content] 写入 [targetFile]；发布失败时
/// 从备份恢复原内容。
///
/// 同一规范化路径的并发调用会在进程内及应用实例间串行，避免 `.tmp`、`.bak`
/// 竞争和进程中断导致的数据丢失。
/// [preserveTargetMode] 启用时，发布新文件前会保留现有目标的权限位。
Future<void> writeFileAtomically(
  File targetFile,
  String content, {
  bool preserveTargetMode = false,
}) {
  return _runWithAtomicWriteLock(
    targetFile,
    (targetFile) => _writeFileAtomicallyLocked(
      targetFile,
      content,
      preserveTargetMode: preserveTargetMode,
    ),
  );
}

/// 以原子替换方式写入字节，避免进程中断时留下半文件。
Future<void> writeBytesFileAtomically(File targetFile, List<int> bytes) {
  return _runWithAtomicWriteLock(
    targetFile,
    (targetFile) => _writeBytesFileAtomicallyLocked(targetFile, bytes),
  );
}

/// 有界读取字节流并原子替换目标文件；失败时保留原目标，且不会把整个内容载入内存。
Future<void> writeByteStreamFileAtomically(
  File targetFile,
  Stream<List<int>> bytes, {
  required int maxBytes,
  Duration idleTimeout = _atomicIoIdleTimeout,
  Duration totalTimeout = _atomicOperationTotalTimeout,
}) {
  requirePositiveInt(maxBytes, 'maxBytes');
  requirePositiveDuration(idleTimeout, 'idleTimeout');
  requirePositiveDuration(totalTimeout, 'totalTimeout');
  final effectiveTotalTimeout = shorterDuration(
    totalTimeout,
    _atomicStreamWriteMaxTotalTimeout,
  );
  return _runWithAtomicWriteLock(
    targetFile,
    (targetFile) => _writeByteStreamFileAtomicallyLocked(
      targetFile,
      bytes,
      maxBytes: maxBytes,
      idleTimeout: shorterDuration(idleTimeout, effectiveTotalTimeout),
      totalTimeout: effectiveTotalTimeout,
    ),
  );
}

/// 在同一原子写入锁内删除文件及全部恢复残留，避免后续启动从旧备份复活已清除数据。
Future<void> deleteFileAtomically(File targetFile) {
  return _runWithAtomicWriteLock(targetFile, (targetFile) async {
    final deadline = MonotonicDeadline(
      _atomicOperationTotalTimeout,
      timeoutMessage: '删除原子文件超过总时限。',
    );
    try {
      // 目标最后删除；中途失败时仍保留目标，避免旧备份在下次启动时复活。
      final artifacts = <File>[
        _atomicBackupFile(targetFile),
        ...await _atomicTempArtifacts(
          targetFile,
          includeIncomplete: true,
          requireComplete: true,
          totalTimeout: deadline.remaining(),
        ),
        targetFile,
      ];
      for (final artifact in artifacts) {
        if (await artifact.exists().timeout(
          deadline.limit(_atomicMetadataTimeout),
        )) {
          await _discardAtomicFile(targetFile, artifact);
        }
      }
    } finally {
      deadline.stop();
    }
  });
}

/// 不把源文件整体载入内存即可复制到 [targetFile]，并保持与写入方法一致的原子发布
/// 和回滚保证。流式复制期间持续执行 [maxBytes] 上限，防止源文件增长后无限占用
/// 内存或磁盘。
Future<void> copyFileAtomically(
  File sourceFile,
  File targetFile, {
  required int maxBytes,
}) {
  requirePositiveInt(maxBytes, 'maxBytes');
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
  return _writeQueue.enqueue<void>(key, () async {
    final processLock = await _acquireAtomicProcessLock(normalizedTargetFile);
    try {
      await operation(normalizedTargetFile);
    } finally {
      await processLock.release();
    }
  });
}

class _AtomicProcessLockLease {
  _AtomicProcessLockLease(this._file);

  final RandomAccessFile _file;
  bool _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    final unlockFuture = Future<void>.sync(() async {
      await _file.unlock();
    });
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
  final deadline = MonotonicDeadline(
    _atomicProcessLockTimeout,
    timeoutMessage: '等待其他原子写入进程超时。',
  );
  try {
    while (true) {
      final remaining = deadline.remainingOrNull();
      if (remaining == null) {
        await _closeAtomicProcessLockFile(handle);
        throw _atomicProcessLockTimeoutException();
      }
      // 使用非阻塞独占锁并自行重试，确保取消与总等待时限由应用控制。
      final lockFuture = handle.lock();
      try {
        await lockFuture.timeout(
          shorterDuration(_atomicProcessLockAttemptTimeout, remaining),
          onTimeout: () => throw _atomicProcessLockTimeoutException(),
        );
        return _AtomicProcessLockLease(handle);
      } on FileSystemException catch (error) {
        if (!_isAtomicProcessLockContention(error)) {
          await _closeAtomicProcessLockFile(handle);
          rethrow;
        }
        final retryBudget = deadline.remainingOrNull();
        if (retryBudget == null) {
          await _closeAtomicProcessLockFile(handle);
          throw _atomicProcessLockTimeoutException();
        }
        await Future<void>.delayed(
          shorterDuration(_atomicProcessLockRetryDelay, retryBudget),
        );
      } on TimeoutException {
        unawaited(_releaseLateAtomicProcessLock(handle, lockFuture));
        rethrow;
      } catch (_) {
        await _closeAtomicProcessLockFile(handle);
        rethrow;
      }
    }
  } finally {
    deadline.stop();
  }
}

TimeoutException _atomicProcessLockTimeoutException() {
  return TimeoutException('等待其他原子写入进程超时。', _atomicProcessLockTimeout);
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
      // 关闭描述符也会释放已经取得的锁。
    }
  } catch (_) {
    // 延迟加锁失败后仍需关闭描述符。
  }
  await _closeAtomicProcessLockFile(handle);
}

Future<File> _atomicProcessLockFile(File targetFile) async {
  final directory = Directory(
    p.join(Directory.systemTemp.path, _atomicProcessLockDirectoryName),
  );
  await createDirectoryBounded(directory, timeout: _atomicProcessLockTimeout);
  var identity = p.normalize(p.absolute(targetFile.path));
  if (Platform.isWindows) identity = identity.toLowerCase();
  final digest = sha256.convert(utf8.encode(identity));
  return File(p.join(directory.path, '$digest$_atomicProcessLockSuffix'));
}

Future<void> _closeAtomicProcessLockFile(RandomAccessFile file) async {
  final closeFuture = Future<void>.sync(() async {
    await file.close();
  });
  try {
    await closeFuture.timeout(_atomicCleanupTimeout);
  } catch (_) {
    unawaited(closeFuture.catchError((Object _, StackTrace _) {}));
  }
}

Future<void> _writeFileAtomicallyLocked(
  File targetFile,
  String content, {
  required bool preserveTargetMode,
}) async {
  await _writeAtomicallyLocked(
    targetFile,
    (tempFile, remainingBudget) => _writeAtomicTempFile(
      tempFile,
      remainingBudget,
      (output, nextOperationTimeout) async {
        var offset = 0;
        while (offset < content.length) {
          final requestedEnd = offset + _atomicTextChunkCodeUnits;
          final end = safeUtf16PrefixCodeUnits(content, requestedEnd);
          final chunk = utf8.encode(content.substring(offset, end));
          await output.run(
            (file) => file.writeFrom(chunk),
            timeout: nextOperationTimeout(),
          );
          offset = end;
        }
      },
    ),
    preserveTargetMode: preserveTargetMode,
  );
}

Future<void> _writeBytesFileAtomicallyLocked(
  File targetFile,
  List<int> bytes,
) async {
  await _writeAtomicallyLocked(
    targetFile,
    (tempFile, remainingBudget) => _writeAtomicTempFile(
      tempFile,
      remainingBudget,
      (output, nextOperationTimeout) async {
        var offset = 0;
        while (offset < bytes.length) {
          final nextOffset = offset + _atomicIoChunkBytes;
          final end = nextOffset < bytes.length ? nextOffset : bytes.length;
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

Future<void> _writeByteStreamFileAtomicallyLocked(
  File targetFile,
  Stream<List<int>> bytes, {
  required int maxBytes,
  required Duration idleTimeout,
  required Duration totalTimeout,
}) async {
  await _writeAtomicallyLocked(
    targetFile,
    (tempFile, remainingBudget) => _writeAtomicTempFile(
      tempFile,
      remainingBudget,
      (output, nextOperationTimeout) async {
        var writtenBytes = 0;
        final boundedStream = bytes.timeout(
          idleTimeout,
          onTimeout: (sink) =>
              sink.addError(TimeoutException('读取原子字节流超时。', idleTimeout)),
        );
        await for (final chunk in boundedStream) {
          remainingBudget();
          if (chunk.isEmpty) continue;
          if (chunk.length > maxBytes - writtenBytes) {
            throw FileSystemException(
              '字节流超过 $maxBytes 字节写入上限。',
              targetFile.path,
            );
          }
          await output.run(
            (file) => file.writeFrom(chunk),
            timeout: nextOperationTimeout(),
          );
          writtenBytes += chunk.length;
        }
      },
    ),
    totalTimeout: totalTimeout,
  );
}

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
      shorterDuration(_atomicIoIdleTimeout, remainingBudget());

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
        shorterDuration(_atomicIoIdleTimeout, remainingBudget());

    final preflightStat = await sourceFile.stat().timeout(
      nextOperationTimeout(),
    );
    if (!isRegularFileStat(preflightStat)) {
      throw FileSystemException('源路径不是普通文件。', sourceFile.path);
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
        throw FileSystemException('源文件在打开前发生变化。', sourceFile.path);
      }
      final sourceLength = await openedInput.run(
        (file) => file.length(),
        timeout: nextOperationTimeout(),
      );
      if (sourceLength < 0 || sourceLength > maxBytes) {
        throw FileSystemException('源文件超过 $maxBytes 字节复制上限。', sourceFile.path);
      }
      if (sourceLength != initialStat.size) {
        throw FileSystemException('源文件在打开前发生变化。', sourceFile.path);
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
          throw FileSystemException('源文件在复制期间发生变化。', sourceFile.path);
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
        throw FileSystemException('源文件在复制期间发生变化。', sourceFile.path);
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
      onTimeout: () => throw TimeoutException('打开原子操作文件超时。', timeout),
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
    // 此处不在调用方关键路径内，等待真实关闭完成，避免合成超时遗留新建工作文件。
    await file.close();
  } catch (_) {
    // 主操作已经超时，清理只做尽力处理。
  }
  if (incompleteFile != null) {
    try {
      if (await incompleteFile.exists().timeout(_atomicCleanupTimeout)) {
        await incompleteFile.delete().timeout(_atomicCleanupTimeout);
      }
    } catch (_) {
      // 最终由过期残留清理兜底。
    }
  }
}

Future<void> _writeAtomicallyLocked(
  File targetFile,
  Future<void> Function(File tempFile, Duration Function() remainingBudget)
  writeTempFile, {
  bool preserveTargetMode = false,
  Duration totalTimeout = _atomicOperationTotalTimeout,
}) async {
  final deadline = MonotonicDeadline(
    totalTimeout,
    timeoutMessage: '原子文件操作超过总时限。',
  );
  Duration remainingBudget() => deadline.remaining();

  final tempFiles = _newAtomicTempFiles(targetFile);
  final workingFile = tempFiles.working;
  final tempFile = tempFiles.ready;
  final backupFile = _atomicBackupFile(targetFile);
  var movedExistingFile = false;
  try {
    await _ensureAtomicParentDirectory(targetFile).timeout(remainingBudget());
    int? targetMode;
    if (preserveTargetMode &&
        !Platform.isWindows &&
        await targetFile.exists().timeout(remainingBudget())) {
      final targetStat = await targetFile.stat().timeout(remainingBudget());
      if (targetStat.type == FileSystemEntityType.file) {
        targetMode = targetStat.mode & 0x1FF;
      }
    }
    await writeTempFile(workingFile, remainingBudget);
    if (targetMode != null) {
      await _setAtomicFileMode(
        workingFile,
        targetMode,
        shorterDuration(_atomicIoIdleTimeout, remainingBudget()),
      );
    }
    if (!await workingFile.exists().timeout(remainingBudget())) {
      throw FileSystemException('原子写入工作文件在完成前消失。', workingFile.path);
    }
    // 文件系统变更不可取消；完整等待原子切换，避免延迟重命名与回滚或后续写入竞争。
    await workingFile.rename(tempFile.path);
    if (!await tempFile.exists().timeout(remainingBudget())) {
      throw FileSystemException('原子写入临时文件在发布前消失。', tempFile.path);
    }
    if (await backupFile.exists().timeout(remainingBudget())) {
      await _discardAtomicFile(targetFile, backupFile);
    }
    if (await targetFile.exists().timeout(remainingBudget())) {
      await targetFile.rename(backupFile.path);
      movedExistingFile = true;
    }
    await tempFile.rename(targetFile.path);
    try {
      if (await backupFile.exists().timeout(remainingBudget())) {
        await _discardAtomicFile(targetFile, backupFile);
      }
    } catch (_) {
      // 新目标已发布，备份清理失败不应覆盖写入结果。
    }
  } catch (_) {
    // 尽力删除临时文件并恢复备份，清理异常不能阻止恢复或覆盖原始异常。
    for (final artifact in <File>[workingFile, tempFile]) {
      try {
        if (await artifact.exists().timeout(_atomicCleanupTimeout)) {
          await artifact.delete().timeout(_atomicCleanupTimeout);
        }
      } catch (_) {
        // 未完成工作文件不会参与恢复，完整就绪文件仍可安全恢复。
      }
    }
    var backupExists = false;
    if (movedExistingFile) {
      try {
        backupExists = await backupFile.exists().timeout(_atomicCleanupTimeout);
      } catch (_) {
        // 元数据检查失败时保留原始异常。
      }
    }
    if (backupExists) {
      var targetDiscarded = false;
      try {
        if (await targetFile.exists().timeout(_atomicCleanupTimeout)) {
          await _discardAtomicFile(targetFile, targetFile);
        }
        targetDiscarded = true;
      } catch (_) {
        // 目标未移出原路径时不能覆盖恢复，旧备份留待下次启动处理。
      }
      if (targetDiscarded) {
        try {
          await backupFile.rename(targetFile.path);
        } catch (_) {
          // 回滚失败时继续抛出原始异常，由调用方呈现问题。
        }
      }
    }
    rethrow;
  } finally {
    deadline.stop();
  }
}

Future<void> _setAtomicFileMode(File file, int mode, Duration timeout) async {
  final result = await runTrackedProcessOrFailed(
    'chmod',
    <String>[mode.toRadixString(8), file.path],
    timeout: timeout,
    tag: _atomicModeProcessTag,
  );
  if (result.exitCode == 0) return;
  final message = '${result.stderr}'.trim();
  throw FileSystemException(
    message.isEmpty ? '无法保留原文件权限。' : message,
    file.path,
  );
}

Future<void> _ensureAtomicParentDirectory(File targetFile) async {
  try {
    await createDirectoryBounded(
      targetFile.parent,
      timeout: _atomicIoIdleTimeout,
    );
  } on FileSystemException {
    // 后续文件操作会在目录仍缺失时给出准确错误。
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

Future<void> _discardAtomicBackupQuietly(
  File targetFile,
  File backupFile,
) async {
  try {
    await _discardAtomicFile(targetFile, backupFile);
  } catch (_) {
    // 备份清理失败不影响完整目标或恢复结果。
  }
}

Future<void> _discardAtomicFile(File targetFile, File file) async {
  final discardFile = _newAtomicDiscardFile(targetFile);
  await file.rename(discardFile.path);
  try {
    await discardFile.delete().timeout(_atomicCleanupTimeout);
  } catch (_) {
    // 唯一废弃路径不会与后续写入竞争，过期后由统一残留清理回收。
  }
}

Future<File?> _newestAtomicTempArtifact(File targetFile) async {
  final deadline = MonotonicDeadline(
    _atomicArtifactProcessingTimeout,
    timeoutMessage: '检查原子写入临时文件超过总时限。',
  );
  try {
    final List<File> artifacts;
    try {
      artifacts = await _atomicTempArtifacts(
        targetFile,
        requireComplete: true,
        totalTimeout: deadline.remaining(),
      );
    } on FileSystemException {
      return null;
    } on TimeoutException {
      return null;
    }
    final stamped = <({File file, DateTime modified})>[];
    for (final file in artifacts) {
      try {
        final stat = await file.stat().timeout(
          deadline.limit(_atomicMetadataTimeout),
        );
        stamped.add((file: file, modified: stat.modified));
      } on FileSystemException {
        // 枚举后消失的文件直接忽略。
      } on TimeoutException {
        return null;
      }
    }
    if (stamped.isEmpty) return null;
    stamped.sort((a, b) => b.modified.compareTo(a.modified));
    return stamped.first.file;
  } finally {
    deadline.stop();
  }
}

Future<void> _deleteStaleAtomicTempArtifacts(File targetFile) async {
  final deadline = MonotonicDeadline(
    _atomicArtifactProcessingTimeout,
    timeoutMessage: '清理原子写入临时文件超过总时限。',
  );
  try {
    final cutoff = DateTime.now().subtract(_atomicStaleArtifactAge);
    final artifacts = await _atomicTempArtifacts(
      targetFile,
      includeIncomplete: true,
      totalTimeout: deadline.remaining(),
    );
    for (final file in artifacts) {
      try {
        final stat = await file.stat().timeout(
          deadline.limit(_atomicMetadataTimeout),
        );
        if (stat.modified.isAfter(cutoff)) continue;
        await file.delete().timeout(deadline.limit(_atomicCleanupTimeout));
      } on TimeoutException {
        return;
      } on FileSystemException {
        // 过期残留清理失败不影响主文件。
      }
    }
  } catch (_) {
    // 清理失败不影响完整目标。
  } finally {
    deadline.stop();
  }
}

Future<List<File>> _atomicTempArtifacts(
  File targetFile, {
  bool includeIncomplete = false,
  bool requireComplete = false,
  Duration totalTimeout = _atomicArtifactScanTimeout,
}) async {
  requirePositiveDuration(totalTimeout, 'totalTimeout');
  final deadline = MonotonicDeadline(
    totalTimeout,
    timeoutMessage: '扫描原子写入残留超过总时限。',
  );
  try {
    final parent = targetFile.parent;
    if (!await parent.exists().timeout(
      deadline.limit(_atomicMetadataTimeout),
    )) {
      return const <File>[];
    }
    final legacyTempPath = '${targetFile.path}$_atomicTempSuffix';
    final uniqueTempPrefix = '$legacyTempPath.';
    final incompleteTempPrefix = '$legacyTempPath$_atomicWritingMarker';
    final artifacts = <File>[];
    final listing = await listDirectoryBounded(
      parent,
      maxEntries: _atomicArtifactScanMaxEntries,
      totalTimeout: deadline.limit(_atomicArtifactScanTimeout),
    );
    if (requireComplete && listing.truncated) {
      throw FileSystemException('原子写入残留扫描未完整结束。', parent.path);
    }
    for (final entity in listing.entries) {
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
    return artifacts;
  } on FileSystemException {
    if (requireComplete) rethrow;
    return const <File>[];
  } finally {
    deadline.stop();
  }
}

/// 使用平台文件管理器打开目录。
///
/// 平台不受支持、目录无效或系统命令失败时抛出 [FileSystemException]。
Future<void> openDirectoryInFileManager(
  Directory directory, {
  bool createIfMissing = true,
}) async {
  final type = await FileSystemEntity.type(
    directory.path,
  ).timeout(_openDirectoryCommandTimeout);
  if (type == FileSystemEntityType.notFound) {
    if (!createIfMissing) {
      throw FileSystemException('目录不存在。', directory.path);
    }
    await createDirectoryBounded(
      directory,
      timeout: _openDirectoryCommandTimeout,
    );
  } else if (type != FileSystemEntityType.directory) {
    throw FileSystemException('路径不是目录。', directory.path);
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
      throw const FileSystemException('当前平台不支持打开目录。');
    }
  } on ProcessException catch (error) {
    throw FileSystemException('打开目录失败：${error.message}');
  }

  // Windows explorer.exe 成功时也可能返回退出码 1，因此不检查其退出码。
  if (result == null) {
    throw const FileSystemException('打开目录命令超时。');
  }
  if (result.exitCode != 0 && !Platform.isWindows) {
    final message = '${result.stderr}'.trim();
    throw FileSystemException(message.isEmpty ? '无法打开目录。' : '无法打开目录：$message');
  }
}
