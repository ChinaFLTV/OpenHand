import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../app/support/silent_log.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/timer_safety.dart';
import 'machine_terminal_service.dart';

const int kMachineTerminalMaxUploadFiles = 20;
const int kMachineTerminalMaxEditableFileBytes = 5 * kBytesPerMiB;
const int _machineTerminalDirectoryEntryLimit = 2000;
const int _machineTerminalReadChunkBytes = 64 * kBytesPerKiB;
const int _machineTerminalMaxTransferRecords = 200;
const int _machineTerminalMaxQueuedOperations = 64;
const int _machineTerminalCommandErrorOutputLimit = 4000;
const int _machineTerminalInlineCommandBytes = 240;
const int _machineTerminalStagedCommandChunkCharacters = 1024;
const int _machineTerminalMaxStagedCommandBytes = 16 * kBytesPerKiB;
const int _machineTerminalMaxStagedPathCharacters = 4096;
const String _machineTerminalReadChunkBegin = '__OPENHAND_FILE_CHUNK__';
const String _machineTerminalReadChunkEnd = '__OPENHAND_FILE_CHUNK_END__';
const String _machineTerminalStagedPathBegin = '__OPENHAND_STAGED_PATH_BEGIN__';
const String _machineTerminalStagedPathEnd = '__OPENHAND_STAGED_PATH_END__';
const Duration _machineTerminalFileCommandTimeout = Duration(seconds: 30);
const Duration _machineTerminalMutationTimeout = Duration(minutes: 5);
const Duration _machineTerminalDownloadTimeout = Duration(minutes: 30);
const Duration _machineTerminalTransferShutdownTimeout = Duration(seconds: 8);
const Duration _machineTerminalProgressNotifyInterval = Duration(
  milliseconds: 60,
);

enum MachineTerminalFileKind { file, directory, link, other }

enum MachineTerminalTransferDirection { upload, download }

enum MachineTerminalTransferStatus {
  queued,
  transferring,
  paused,
  completed,
  failed,
  canceled,
}

@immutable
class MachineTerminalFileEntry {
  const MachineTerminalFileEntry({
    required this.name,
    required this.path,
    required this.kind,
    required this.size,
    required this.modifiedAt,
    required this.permissions,
    this.linkTarget,
    this.childDirectoryCount = 0,
    this.childFileCount = 0,
  });

  final String name;
  final String path;
  final MachineTerminalFileKind kind;
  final int size;
  final DateTime? modifiedAt;
  final String permissions;
  final String? linkTarget;
  final int childDirectoryCount;
  final int childFileCount;

  bool get isDirectory => kind == MachineTerminalFileKind.directory;
  bool get isFile => kind == MachineTerminalFileKind.file;
  bool get isLink => kind == MachineTerminalFileKind.link;
}

@immutable
class MachineTerminalDirectorySnapshot {
  const MachineTerminalDirectorySnapshot({
    required this.path,
    required this.entries,
    required this.truncated,
    required this.windowsPath,
  });

  final String path;
  final List<MachineTerminalFileEntry> entries;
  final bool truncated;
  final bool windowsPath;
}

@immutable
class MachineTerminalFileDetails {
  const MachineTerminalFileDetails({
    required this.entry,
    required this.mimeType,
    required this.owner,
    required this.group,
    required this.inode,
    required this.createdAt,
    required this.accessedAt,
    required this.changedAt,
  });

  final MachineTerminalFileEntry entry;
  final String mimeType;
  final String owner;
  final String group;
  final String inode;
  final DateTime? createdAt;
  final DateTime? accessedAt;
  final DateTime? changedAt;
}

@immutable
class MachineTerminalTransferTask {
  const MachineTerminalTransferTask({
    required this.id,
    required this.sessionId,
    required this.terminalId,
    required this.direction,
    required this.sourcePath,
    required this.targetDirectory,
    required this.fileName,
    required this.totalBytes,
    required this.transferredBytes,
    required this.status,
    required this.createdAt,
    this.speedBytesPerSecond = 0,
    this.startedAt,
    this.completedAt,
    this.error,
  });

  final String id;
  final String sessionId;
  final String terminalId;
  final MachineTerminalTransferDirection direction;
  final String sourcePath;
  final String targetDirectory;
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final MachineTerminalTransferStatus status;
  final DateTime createdAt;
  final double speedBytesPerSecond;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? error;

  double get progress => totalBytes <= 0
      ? status == MachineTerminalTransferStatus.completed
            ? 1
            : 0
      : (transferredBytes / totalBytes).clamp(0, 1);

  bool get isActive =>
      status == MachineTerminalTransferStatus.queued ||
      status == MachineTerminalTransferStatus.transferring ||
      status == MachineTerminalTransferStatus.paused;

  Duration get elapsed {
    final start = startedAt;
    if (start == null) return Duration.zero;
    final end = completedAt ?? DateTime.now();
    final value = end.difference(start);
    return value.isNegative ? Duration.zero : value;
  }

  double get effectiveSpeedBytesPerSecond {
    if (status == MachineTerminalTransferStatus.paused) return 0;
    if (status == MachineTerminalTransferStatus.transferring &&
        speedBytesPerSecond > 0) {
      return speedBytesPerSecond;
    }
    final milliseconds = elapsed.inMilliseconds;
    if (milliseconds > 0 && transferredBytes > 0) {
      return transferredBytes * Duration.millisecondsPerSecond / milliseconds;
    }
    return speedBytesPerSecond;
  }

  Duration? get estimatedRemaining {
    if (!isActive || totalBytes <= transferredBytes) return null;
    final speed = effectiveSpeedBytesPerSecond;
    if (speed <= 0) return null;
    return Duration(
      milliseconds: ((totalBytes - transferredBytes) / speed * 1000).ceil(),
    );
  }
}

class MachineTerminalFileService extends ChangeNotifier {
  MachineTerminalFileService(this._terminalService);

  final MachineTerminalService _terminalService;
  final Map<String, _MachineTerminalOperationGate> _operationGates =
      <String, _MachineTerminalOperationGate>{};
  final List<_MutableTransferTask> _transferTasks = <_MutableTransferTask>[];
  final Map<String, Future<void>> _transferWorkers = <String, Future<void>>{};
  Timer? _progressNotifyTimer;
  int _transferCounter = 0;
  bool _disposed = false;

  List<MachineTerminalTransferTask> transfers({
    String? sessionId,
    String? terminalId,
  }) {
    return List<MachineTerminalTransferTask>.unmodifiable(
      _transferTasks
          .where(
            (task) =>
                (sessionId == null || task.sessionId == sessionId) &&
                (terminalId == null || task.terminalId == terminalId),
          )
          .map((task) => task.snapshot()),
    );
  }

  Future<MachineTerminalDirectorySnapshot> listDirectory({
    required String sessionId,
    required String terminalId,
    String? path,
  }) {
    return _withTerminalGate(
      sessionId,
      terminalId,
      () => _listDirectory(sessionId, terminalId, path),
    );
  }

  Future<MachineTerminalFileDetails> fileDetails({
    required String sessionId,
    required String terminalId,
    required String path,
  }) {
    return _withTerminalGate(
      sessionId,
      terminalId,
      () => _fileDetails(sessionId, terminalId, path),
    );
  }

  Future<String> readTextFile({
    required String sessionId,
    required String terminalId,
    required MachineTerminalFileEntry entry,
  }) {
    return _withTerminalGate(sessionId, terminalId, () async {
      if (!entry.isFile || entry.size >= kMachineTerminalMaxEditableFileBytes) {
        throw StateError('仅支持编辑小于 5 MB 的普通文本文件。');
      }
      final bytes = <int>[];
      final chunkCount = math.max(
        1,
        (entry.size / _machineTerminalReadChunkBytes).ceil(),
      );
      for (var index = 0; index < chunkCount; index++) {
        final output = await _runCommand(
          sessionId: sessionId,
          terminalId: terminalId,
          command: _readChunkCommand(entry.path, index),
          timeout: _machineTerminalFileCommandTimeout,
        );
        final match = _machineTerminalReadChunkPattern.firstMatch(output);
        if (match == null) throw const FormatException('无法解析文件内容分块。');
        final encoded = match.group(1)!;
        if (encoded.isNotEmpty) bytes.addAll(base64Decode(encoded));
      }
      if (bytes.length != entry.size) {
        throw StateError('文件读取期间发生变化，请刷新后重试。');
      }
      try {
        return utf8.decode(bytes);
      } on FormatException {
        throw StateError('文件不是有效的 UTF-8 文本。');
      }
    });
  }

  Future<void> downloadFile({
    required String sessionId,
    required String terminalId,
    required String sourcePath,
    required String destinationPath,
  }) {
    return _withTerminalGate(
      sessionId,
      terminalId,
      () => _downloadFile(
        sessionId: sessionId,
        terminalId: terminalId,
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        onTotalBytes: (_) {},
        onProgress: (_) {},
        waitWhilePaused: () async {},
        isCancelled: () => false,
      ),
    );
  }

  Future<void> writeTextFile({
    required String sessionId,
    required String terminalId,
    required String path,
    required String content,
  }) {
    return _withTerminalGate(sessionId, terminalId, () async {
      final bytes = utf8.encode(content);
      if (bytes.length >= kMachineTerminalMaxEditableFileBytes) {
        throw StateError('编辑后的文件必须小于 5 MB。');
      }
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'openhand-terminal-edit-',
      );
      final localFile = File(p.join(temporaryDirectory.path, 'content.tmp'));
      try {
        await localFile.writeAsBytes(bytes, flush: true);
        await _terminalService.uploadFile(
          sessionId: sessionId,
          terminalId: terminalId,
          sourcePath: localFile.path,
          targetDirectory: machineTerminalParentPath(path),
          targetName: machineTerminalBaseName(path),
          onProgress: (_) {},
          waitWhilePaused: () async {},
          isCancelled: () => false,
          recordHistory: false,
        );
      } finally {
        try {
          await temporaryDirectory.delete(recursive: true);
        } catch (error, stack) {
          silentLog('machine_terminal_file', '清理编辑临时文件', error, stack);
        }
      }
    });
  }

  Future<void> rename({
    required String sessionId,
    required String terminalId,
    required String sourcePath,
    required String newName,
  }) {
    final normalizedName = _validatedFileName(newName);
    final targetPath = machineTerminalJoinPath(
      machineTerminalParentPath(sourcePath),
      normalizedName,
    );
    return move(
      sessionId: sessionId,
      terminalId: terminalId,
      sourcePath: sourcePath,
      targetPath: targetPath,
    );
  }

  Future<void> move({
    required String sessionId,
    required String terminalId,
    required String sourcePath,
    required String targetPath,
  }) {
    return _runMutation(
      sessionId,
      terminalId,
      _moveCommand(sourcePath, targetPath),
    );
  }

  Future<void> copy({
    required String sessionId,
    required String terminalId,
    required String sourcePath,
    required String targetPath,
  }) {
    return _runMutation(
      sessionId,
      terminalId,
      _copyCommand(sourcePath, targetPath),
    );
  }

  Future<void> delete({
    required String sessionId,
    required String terminalId,
    required String path,
  }) {
    return _runMutation(sessionId, terminalId, _deleteCommand(path));
  }

  Future<List<String>> enqueueUploads({
    required String sessionId,
    required String terminalId,
    required String targetDirectory,
    required List<String> sourcePaths,
  }) async {
    if (sourcePaths.isEmpty) return const <String>[];
    if (sourcePaths.length > kMachineTerminalMaxUploadFiles) {
      throw ArgumentError('一次最多选择 $kMachineTerminalMaxUploadFiles 个文件。');
    }
    final sources = <({String path, String fileName, int size})>[];
    for (final sourcePath in sourcePaths) {
      final stat = await File(sourcePath).stat();
      if (stat.type != FileSystemEntityType.file) {
        throw FileSystemException('上传源不是普通文件。', sourcePath);
      }
      sources.add((
        path: sourcePath,
        fileName: _validatedFileName(p.basename(sourcePath)),
        size: stat.size,
      ));
    }
    final createdIds = <String>[];
    for (final source in sources) {
      final id =
          'transfer-${DateTime.now().microsecondsSinceEpoch}-${++_transferCounter}';
      _transferTasks.add(
        _MutableTransferTask(
          id: id,
          sessionId: sessionId,
          terminalId: terminalId,
          direction: MachineTerminalTransferDirection.upload,
          sourcePath: source.path,
          targetDirectory: targetDirectory,
          fileName: source.fileName,
          totalBytes: source.size,
        ),
      );
      createdIds.add(id);
    }
    _trimTransferRecords();
    _notify();
    _startTransferWorker(_terminalKey(sessionId, terminalId));
    return createdIds;
  }

  String enqueueDownload({
    required String sessionId,
    required String terminalId,
    required String sourcePath,
    required String destinationPath,
    required int totalBytes,
  }) {
    if (sourcePath.trim().isEmpty || destinationPath.trim().isEmpty) {
      throw ArgumentError('下载路径不能为空。');
    }
    if (totalBytes < 0) throw ArgumentError.value(totalBytes, 'totalBytes');
    final id =
        'transfer-${DateTime.now().microsecondsSinceEpoch}-${++_transferCounter}';
    _transferTasks.add(
      _MutableTransferTask(
        id: id,
        sessionId: sessionId,
        terminalId: terminalId,
        direction: MachineTerminalTransferDirection.download,
        sourcePath: sourcePath,
        targetDirectory: p.dirname(destinationPath),
        fileName: _validatedFileName(p.basename(destinationPath), trim: false),
        totalBytes: totalBytes,
      ),
    );
    _trimTransferRecords();
    _notify();
    _startTransferWorker(_terminalKey(sessionId, terminalId));
    return id;
  }

  void pauseTransfer(String taskId) {
    final task = _taskById(taskId);
    if (task == null ||
        (task.status != MachineTerminalTransferStatus.queued &&
            task.status != MachineTerminalTransferStatus.transferring)) {
      return;
    }
    task.statusBeforePause = task.status;
    task.status = MachineTerminalTransferStatus.paused;
    task.resetProgressClock();
    task.pauseSignal ??= Completer<void>();
    _notify();
  }

  void resumeTransfer(String taskId) {
    final task = _taskById(taskId);
    if (task == null || task.status != MachineTerminalTransferStatus.paused) {
      return;
    }
    task.status = task.statusBeforePause;
    task.resetProgressClock();
    task.pauseSignal?.complete();
    task.pauseSignal = null;
    _notify();
    _startTransferWorker(_terminalKey(task.sessionId, task.terminalId));
  }

  void cancelTransfer(String taskId) {
    final task = _taskById(taskId);
    if (task == null || !task.snapshot().isActive) return;
    task.status = MachineTerminalTransferStatus.canceled;
    task.completedAt = DateTime.now();
    task.pauseSignal?.complete();
    task.pauseSignal = null;
    _notify();
  }

  void deleteTransfer(String taskId) {
    final task = _taskById(taskId);
    if (task == null) return;
    if (task.snapshot().isActive) {
      task.removeWhenFinished = true;
      cancelTransfer(taskId);
      if (task.startedAt == null) {
        _transferTasks.remove(task);
        _notify();
      }
      return;
    }
    _transferTasks.remove(task);
    _notify();
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    _progressNotifyTimer?.cancel();
    for (final task in _transferTasks) {
      if (task.snapshot().isActive) {
        task.status = MachineTerminalTransferStatus.canceled;
        task.pauseSignal?.complete();
        task.pauseSignal = null;
      }
    }
    try {
      await Future.wait<void>(
        _transferWorkers.values,
      ).timeout(_machineTerminalTransferShutdownTimeout);
    } catch (error, stack) {
      silentLog('machine_terminal_file', '停止文件传输队列', error, stack);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _progressNotifyTimer?.cancel();
    super.dispose();
  }

  Future<MachineTerminalDirectorySnapshot> _listDirectory(
    String sessionId,
    String terminalId,
    String? path,
  ) async {
    final output = await _runCommand(
      sessionId: sessionId,
      terminalId: terminalId,
      command: _listDirectoryCommand(path),
      timeout: _machineTerminalFileCommandTimeout,
    );
    return parseMachineTerminalDirectoryProtocol(
      output,
      windowsPath: Platform.isWindows,
    );
  }

  Future<MachineTerminalFileDetails> _fileDetails(
    String sessionId,
    String terminalId,
    String path,
  ) async {
    final output = await _runCommand(
      sessionId: sessionId,
      terminalId: terminalId,
      command: _fileDetailsCommand(path),
      timeout: _machineTerminalFileCommandTimeout,
    );
    try {
      return parseMachineTerminalFileDetailsProtocol(
        output,
        requestedPath: path,
      );
    } on FormatException catch (error) {
      throw FormatException(
        '${error.message}\n${clipText(output, _machineTerminalCommandErrorOutputLimit)}',
      );
    }
  }

  Future<void> _downloadFile({
    required String sessionId,
    required String terminalId,
    required String sourcePath,
    required String destinationPath,
    required ValueChanged<int> onTotalBytes,
    required MachineTerminalUploadProgress onProgress,
    required MachineTerminalUploadPauseWaiter waitWhilePaused,
    required MachineTerminalUploadCancelCheck isCancelled,
  }) async {
    final before = await _fileDetails(sessionId, terminalId, sourcePath);
    if (!before.entry.isFile) throw StateError('仅支持下载普通文件。');
    final expectedBytes = before.entry.size;
    onTotalBytes(expectedBytes);
    var downloadedBytes = 0;

    Stream<List<int>> chunks() async* {
      final chunkCount = math.max(
        1,
        (expectedBytes / _machineTerminalReadChunkBytes).ceil(),
      );
      for (var index = 0; index < chunkCount; index++) {
        await waitWhilePaused();
        if (isCancelled()) throw const MachineTerminalUploadCancelled();
        final output = await _runCommand(
          sessionId: sessionId,
          terminalId: terminalId,
          command: _readChunkCommand(before.entry.path, index),
          timeout: _machineTerminalFileCommandTimeout,
        );
        final match = _machineTerminalReadChunkPattern.firstMatch(output);
        if (match == null) throw const FormatException('无法解析下载文件分块。');
        final encoded = match.group(1)!;
        final chunk = encoded.isEmpty ? const <int>[] : base64Decode(encoded);
        if (chunk.length > expectedBytes - downloadedBytes) {
          throw StateError('文件下载期间发生变化，请刷新后重试。');
        }
        downloadedBytes += chunk.length;
        onProgress(downloadedBytes);
        if (chunk.isNotEmpty) yield chunk;
      }
      if (downloadedBytes != expectedBytes) {
        throw StateError('文件下载期间发生变化，请刷新后重试。');
      }
      if (isCancelled()) throw const MachineTerminalUploadCancelled();
      final after = await _fileDetails(sessionId, terminalId, sourcePath);
      if (isCancelled()) throw const MachineTerminalUploadCancelled();
      if (!after.entry.isFile ||
          after.entry.size != expectedBytes ||
          after.entry.modifiedAt != before.entry.modifiedAt) {
        throw StateError('文件下载期间发生变化，请刷新后重试。');
      }
    }

    await writeByteStreamFileAtomically(
      File(destinationPath),
      chunks(),
      maxBytes: math.max(1, expectedBytes),
      idleTimeout: _machineTerminalDownloadTimeout,
      totalTimeout: _machineTerminalDownloadTimeout,
    );
  }

  Future<void> _runMutation(
    String sessionId,
    String terminalId,
    String command,
  ) {
    return _withTerminalGate(sessionId, terminalId, () async {
      await _runCommand(
        sessionId: sessionId,
        terminalId: terminalId,
        command: command,
        timeout: _machineTerminalMutationTimeout,
      );
    });
  }

  Future<String> _runCommand({
    required String sessionId,
    required String terminalId,
    required String command,
    required Duration timeout,
  }) async {
    final commandBytes = utf8.encode(command).length;
    if (!Platform.isWindows &&
        commandBytes > _machineTerminalInlineCommandBytes) {
      if (commandBytes > _machineTerminalMaxStagedCommandBytes) {
        throw StateError('远端文件命令过长。');
      }
      return _runStagedPosixCommand(
        sessionId: sessionId,
        terminalId: terminalId,
        command: command,
        timeout: timeout,
      );
    }
    return _runInlineCommand(
      sessionId: sessionId,
      terminalId: terminalId,
      command: command,
      timeout: timeout,
    );
  }

  Future<String> _runStagedPosixCommand({
    required String sessionId,
    required String terminalId,
    required String command,
    required Duration timeout,
  }) async {
    final temporaryOutput = await _runInlineCommand(
      sessionId: sessionId,
      terminalId: terminalId,
      command:
          '__oh_tmp=\$(mktemp "\${TMPDIR:-/tmp}/openhand-command.XXXXXX") || exit 1; '
          'printf "$_machineTerminalStagedPathBegin%s$_machineTerminalStagedPathEnd\\n" '
          '"\$(printf "%s" "\$__oh_tmp" | base64 | tr -d "\\r\\n")"',
      timeout: _machineTerminalFileCommandTimeout,
    );
    final temporaryPath = parseMachineTerminalStagedPathProtocol(
      temporaryOutput,
    );
    final encoded = base64Encode(utf8.encode(command));
    try {
      for (
        var offset = 0;
        offset < encoded.length;
        offset += _machineTerminalStagedCommandChunkCharacters
      ) {
        final end = math.min(
          offset + _machineTerminalStagedCommandChunkCharacters,
          encoded.length,
        );
        await _runInlineCommand(
          sessionId: sessionId,
          terminalId: terminalId,
          command:
              "printf '%s' '${encoded.substring(offset, end)}' >> ${_quotePosix(temporaryPath)}",
          timeout: _machineTerminalFileCommandTimeout,
        );
      }
      return await _runInlineCommand(
        sessionId: sessionId,
        terminalId: terminalId,
        command:
            '__oh_script=${_quotePosix(temporaryPath)}; '
            'base64 -d < "\$__oh_script" | sh; '
            '__oh_status=\$?; rm -f -- "\$__oh_script"; exit "\$__oh_status"',
        timeout: timeout,
      );
    } finally {
      try {
        await _runInlineCommand(
          sessionId: sessionId,
          terminalId: terminalId,
          command: 'rm -f -- ${_quotePosix(temporaryPath)}',
          timeout: _machineTerminalFileCommandTimeout,
        );
      } catch (error, stack) {
        silentLog('machine_terminal_file', '清理远端命令临时文件', error, stack);
      }
    }
  }

  Future<String> _runInlineCommand({
    required String sessionId,
    required String terminalId,
    required String command,
    required Duration timeout,
  }) async {
    final result = await _terminalService.executeCommand(
      sessionId: sessionId,
      terminalId: terminalId,
      command: command,
      timeout: timeout,
      recordHistory: false,
    );
    if (result.succeeded) return result.output;
    final error = result.error?.trim() ?? '';
    final output = result.output.trim();
    final message = error.isNotEmpty
        ? output.isEmpty
              ? error
              : '$error\n${clipText(output, _machineTerminalCommandErrorOutputLimit)}'
        : output.isNotEmpty
        ? clipText(output, _machineTerminalCommandErrorOutputLimit)
        : '远端文件操作失败。';
    throw StateError(message);
  }

  Future<T> _withTerminalGate<T>(
    String sessionId,
    String terminalId,
    Future<T> Function() operation,
  ) {
    final key = _terminalKey(sessionId, terminalId);
    final gate = _operationGates.putIfAbsent(
      key,
      _MachineTerminalOperationGate.new,
    );
    return gate.run(operation).whenComplete(() {
      if (gate.isIdle && identical(_operationGates[key], gate)) {
        _operationGates.remove(key);
      }
    });
  }

  void _startTransferWorker(String key) {
    if (_disposed || _transferWorkers.containsKey(key)) return;
    late final Future<void> worker;
    worker = _runTransferQueue(key).whenComplete(() {
      if (identical(_transferWorkers[key], worker)) {
        _transferWorkers.remove(key);
      }
      if (!_disposed && _nextPendingTransfer(key) != null) {
        _startTransferWorker(key);
      }
    });
    _transferWorkers[key] = worker;
  }

  Future<void> _runTransferQueue(String key) async {
    while (!_disposed) {
      final task = _nextPendingTransfer(key);
      if (task == null) return;
      if (task.status == MachineTerminalTransferStatus.paused) {
        await _waitWhilePaused(task);
        continue;
      }
      if (task.status != MachineTerminalTransferStatus.queued) continue;
      task
        ..status = MachineTerminalTransferStatus.transferring
        ..startedAt = DateTime.now()
        ..error = null;
      _notify();
      try {
        await _withTerminalGate(task.sessionId, task.terminalId, () async {
          if (task.status == MachineTerminalTransferStatus.canceled) {
            throw const MachineTerminalUploadCancelled();
          }
          void onProgress(int bytes) {
            task.updateProgress(bytes);
            _scheduleProgressNotify();
          }

          bool isCancelled() =>
              _disposed ||
              task.status == MachineTerminalTransferStatus.canceled;
          if (task.direction == MachineTerminalTransferDirection.upload) {
            await _terminalService.uploadFile(
              sessionId: task.sessionId,
              terminalId: task.terminalId,
              sourcePath: task.sourcePath,
              targetDirectory: task.targetDirectory,
              targetName: task.fileName,
              onProgress: onProgress,
              waitWhilePaused: () => _waitWhilePaused(task),
              isCancelled: isCancelled,
              recordHistory: false,
            );
          } else {
            await _downloadFile(
              sessionId: task.sessionId,
              terminalId: task.terminalId,
              sourcePath: task.sourcePath,
              destinationPath: p.join(task.targetDirectory, task.fileName),
              onTotalBytes: (bytes) {
                task.totalBytes = bytes;
                if (task.transferredBytes > bytes) {
                  task.transferredBytes = bytes;
                  task.resetProgressClock();
                }
                task.updateProgress(task.transferredBytes);
                _scheduleProgressNotify();
              },
              onProgress: onProgress,
              waitWhilePaused: () => _waitWhilePaused(task),
              isCancelled: isCancelled,
            );
          }
        });
        if (task.status != MachineTerminalTransferStatus.canceled) {
          task
            ..status = MachineTerminalTransferStatus.completed
            ..completedAt = DateTime.now();
          task.updateProgress(task.totalBytes);
        }
      } on MachineTerminalUploadCancelled {
        task
          ..status = MachineTerminalTransferStatus.canceled
          ..completedAt ??= DateTime.now();
      } catch (error, stack) {
        task
          ..status = MachineTerminalTransferStatus.failed
          ..error = clipText('$error', 1200)
          ..completedAt = DateTime.now();
        silentLog(
          'machine_terminal_file',
          '${task.direction == MachineTerminalTransferDirection.upload ? '上传' : '下载'}文件 ${task.fileName}',
          error,
          stack,
        );
      } finally {
        if (task.removeWhenFinished) _transferTasks.remove(task);
        _notify();
      }
    }
  }

  Future<void> _waitWhilePaused(_MutableTransferTask task) async {
    while (!_disposed && task.status == MachineTerminalTransferStatus.paused) {
      task.pauseSignal ??= Completer<void>();
      await task.pauseSignal!.future;
    }
  }

  _MutableTransferTask? _nextPendingTransfer(String key) {
    for (final task in _transferTasks) {
      if (_terminalKey(task.sessionId, task.terminalId) == key &&
          (task.status == MachineTerminalTransferStatus.queued ||
              task.status == MachineTerminalTransferStatus.paused)) {
        return task;
      }
    }
    return null;
  }

  _MutableTransferTask? _taskById(String taskId) {
    for (final task in _transferTasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  void _scheduleProgressNotify() {
    if (_disposed || _progressNotifyTimer != null) return;
    _progressNotifyTimer = startSafeTimer(
      _machineTerminalProgressNotifyInterval,
      () {
        _progressNotifyTimer = null;
        _notify();
      },
    );
  }

  void _trimTransferRecords() {
    while (_transferTasks.length > _machineTerminalMaxTransferRecords) {
      final index = _transferTasks.indexWhere(
        (task) => !task.snapshot().isActive,
      );
      if (index < 0) return;
      _transferTasks.removeAt(index);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

String parseMachineTerminalStagedPathProtocol(String output) {
  String? temporaryPath;
  for (final match in _machineTerminalStagedPathPattern.allMatches(output)) {
    try {
      final path = utf8.decode(base64Decode(match.group(1)!));
      if (path.length <= _machineTerminalMaxStagedPathCharacters &&
          path.startsWith('/') &&
          !_machineTerminalUnsafePathCharacterPattern.hasMatch(path) &&
          !path
              .split('/')
              .any((segment) => segment == '.' || segment == '..') &&
          _machineTerminalStagedFilePathPattern.hasMatch(path)) {
        temporaryPath = path;
      }
    } on FormatException {
      continue;
    }
  }
  if (temporaryPath == null) {
    throw StateError('无法创建远端命令临时文件。');
  }
  return temporaryPath;
}

MachineTerminalDirectorySnapshot parseMachineTerminalDirectoryProtocol(
  String output, {
  required bool windowsPath,
}) {
  String? directoryPath;
  var truncated = false;
  final entriesByPath = <String, MachineTerminalFileEntry>{};
  for (final line in const LineSplitter().convert(output)) {
    final pathMarker = line.indexOf('P\t');
    final entryMarker = line.indexOf('E\t');
    final protocolLine = pathMarker >= 0
        ? line.substring(pathMarker)
        : entryMarker >= 0
        ? line.substring(entryMarker)
        : line.trim();
    final fields = protocolLine.split('\t');
    if (fields.isEmpty) continue;
    if (fields.first == 'P' && fields.length >= 2) {
      directoryPath = _decodeProtocolText(fields[1]);
      continue;
    }
    if (fields.first == 'T') {
      truncated = true;
      continue;
    }
    if (fields.first != 'E' || fields.length < 7 || directoryPath == null) {
      continue;
    }
    final name = _decodeProtocolText(fields[5]);
    if (name.isEmpty || name == '.' || name == '..') continue;
    final path = machineTerminalJoinPath(directoryPath, name);
    entriesByPath[path] = MachineTerminalFileEntry(
      name: name,
      path: path,
      kind: _kindFromProtocol(fields[1]),
      size: int.tryParse(fields[2]) ?? 0,
      modifiedAt: _dateTimeFromEpoch(fields[3]),
      permissions: fields[4],
      linkTarget: fields[6].isEmpty ? null : _decodeProtocolText(fields[6]),
      childDirectoryCount: fields.length > 7 ? int.tryParse(fields[7]) ?? 0 : 0,
      childFileCount: fields.length > 8 ? int.tryParse(fields[8]) ?? 0 : 0,
    );
  }
  if (directoryPath == null || directoryPath.isEmpty) {
    throw const FormatException('无法解析当前终端目录。');
  }
  final entries = entriesByPath.values.toList(growable: false)
    ..sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return MachineTerminalDirectorySnapshot(
    path: directoryPath,
    entries: entries,
    truncated: truncated,
    windowsPath: windowsPath,
  );
}

MachineTerminalFileDetails parseMachineTerminalFileDetailsProtocol(
  String output, {
  required String requestedPath,
}) {
  for (final line in const LineSplitter().convert(output)) {
    final marker = line.indexOf('D\t');
    if (marker < 0) continue;
    final fields = line.substring(marker).split('\t');
    if (fields.length < 14 || fields.first != 'D') continue;
    final decodedPath = _decodeProtocolText(fields[2]);
    final path = decodedPath.isEmpty ? requestedPath : decodedPath;
    final entry = MachineTerminalFileEntry(
      name: machineTerminalBaseName(path),
      path: path,
      kind: _kindFromProtocol(fields[1]),
      size: int.tryParse(fields[3]) ?? 0,
      modifiedAt: _dateTimeFromEpoch(fields[4]),
      permissions: fields[5],
      linkTarget: fields[10].isEmpty ? null : _decodeProtocolText(fields[10]),
      childDirectoryCount: fields.length > 14
          ? int.tryParse(fields[14]) ?? 0
          : 0,
      childFileCount: fields.length > 15 ? int.tryParse(fields[15]) ?? 0 : 0,
    );
    return MachineTerminalFileDetails(
      entry: entry,
      owner: _decodeProtocolText(fields[6]),
      group: _decodeProtocolText(fields[7]),
      inode: fields[8],
      mimeType: _decodeProtocolText(fields[9]),
      createdAt: _dateTimeFromEpoch(fields[11]),
      accessedAt: _dateTimeFromEpoch(fields[12]),
      changedAt: _dateTimeFromEpoch(fields[13]),
    );
  }
  throw const FormatException('无法解析文件详情。');
}

String machineTerminalJoinPath(String directory, String name) {
  final separator = directory.contains(r'\') && !directory.contains('/')
      ? r'\'
      : '/';
  if (directory.endsWith('/') || directory.endsWith(r'\')) {
    return '$directory$name';
  }
  return '$directory$separator$name';
}

String machineTerminalParentPath(String path) {
  final normalized = path.replaceAll(r'\', '/');
  if (RegExp(r'^[A-Za-z]:/$').hasMatch(normalized) || normalized == '/') {
    return path;
  }
  final slash = normalized.lastIndexOf('/');
  if (slash < 0) return '.';
  final parent = slash == 0 ? '/' : normalized.substring(0, slash);
  return path.contains(r'\') && !path.contains('/')
      ? parent.replaceAll('/', r'\')
      : parent;
}

String machineTerminalBaseName(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final trimmed = normalized.endsWith('/') && normalized.length > 1
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final slash = trimmed.lastIndexOf('/');
  return slash < 0 ? trimmed : trimmed.substring(slash + 1);
}

class _MutableTransferTask {
  _MutableTransferTask({
    required this.id,
    required this.sessionId,
    required this.terminalId,
    required this.direction,
    required this.sourcePath,
    required this.targetDirectory,
    required this.fileName,
    required this.totalBytes,
  }) : createdAt = DateTime.now();

  final String id;
  final String sessionId;
  final String terminalId;
  final MachineTerminalTransferDirection direction;
  final String sourcePath;
  final String targetDirectory;
  final String fileName;
  int totalBytes;
  final DateTime createdAt;
  int transferredBytes = 0;
  double speedBytesPerSecond = 0;
  MachineTerminalTransferStatus status = MachineTerminalTransferStatus.queued;
  MachineTerminalTransferStatus statusBeforePause =
      MachineTerminalTransferStatus.queued;
  DateTime? startedAt;
  DateTime? completedAt;
  String? error;
  Completer<void>? pauseSignal;
  bool removeWhenFinished = false;
  DateTime? _lastProgressAt;

  void updateProgress(int bytes) {
    final next = bytes.clamp(0, totalBytes).toInt();
    if (next < transferredBytes) return;
    final now = DateTime.now();
    final previousAt = _lastProgressAt;
    if (previousAt != null && next > transferredBytes) {
      final elapsedMs = now.difference(previousAt).inMilliseconds;
      if (elapsedMs > 0) {
        speedBytesPerSecond =
            (next - transferredBytes) *
            Duration.millisecondsPerSecond /
            elapsedMs;
      }
    }
    transferredBytes = next;
    _lastProgressAt = now;
  }

  void resetProgressClock() {
    speedBytesPerSecond = 0;
    _lastProgressAt = null;
  }

  MachineTerminalTransferTask snapshot() => MachineTerminalTransferTask(
    id: id,
    sessionId: sessionId,
    terminalId: terminalId,
    direction: direction,
    sourcePath: sourcePath,
    targetDirectory: targetDirectory,
    fileName: fileName,
    totalBytes: totalBytes,
    transferredBytes: transferredBytes,
    status: status,
    createdAt: createdAt,
    speedBytesPerSecond: speedBytesPerSecond,
    startedAt: startedAt,
    completedAt: completedAt,
    error: error,
  );
}

class _MachineTerminalOperationGate {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  bool get isIdle => _pending == 0;

  Future<T> run<T>(Future<T> Function() operation) async {
    if (_pending >= _machineTerminalMaxQueuedOperations) {
      throw StateError('终端文件操作队列已满。');
    }
    _pending += 1;
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    await previous;
    try {
      return await operation();
    } finally {
      _pending -= 1;
      release.complete();
    }
  }
}

String _terminalKey(String sessionId, String terminalId) =>
    '$sessionId\u0000$terminalId';

String _validatedFileName(String value, {bool trim = true}) {
  final name = trim ? value.trim() : value;
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains(r'\') ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(name)) {
    throw ArgumentError.value(value, 'name', '文件名无效。');
  }
  return name;
}

MachineTerminalFileKind _kindFromProtocol(String value) => switch (value) {
  'd' => MachineTerminalFileKind.directory,
  'f' => MachineTerminalFileKind.file,
  'l' => MachineTerminalFileKind.link,
  _ => MachineTerminalFileKind.other,
};

DateTime? _dateTimeFromEpoch(String value) {
  final seconds = int.tryParse(value);
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

String _decodeProtocolText(String value) {
  if (value.isEmpty) return '';
  return utf8.decode(base64Decode(value), allowMalformed: true);
}

String _listDirectoryCommand(String? path) {
  if (Platform.isWindows) {
    const entryLimitWithSentinel = _machineTerminalDirectoryEntryLimit + 1;
    final pathLiteral = path == null
        ? r'(Get-Location).ProviderPath'
        : "[IO.Path]::GetFullPath('${_escapePowerShell(path)}')";
    final script =
        '''
\$ErrorActionPreference = 'Stop'
function B64([string]\$value) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(\$value)) }
\$directory = $pathLiteral
Set-Location -LiteralPath \$directory
\$resolved = (Get-Location).ProviderPath
Write-Output ("P`t" + (B64 \$resolved))
\$items = @(Get-ChildItem -LiteralPath \$resolved -Force | Select-Object -First $entryLimitWithSentinel)
\$items | Select-Object -First $_machineTerminalDirectoryEntryLimit | ForEach-Object {
  \$item = \$_
  \$kind = if (\$item.Attributes -band [IO.FileAttributes]::ReparsePoint) { 'l' } elseif (\$item.PSIsContainer) { 'd' } else { 'f' }
  \$size = if (\$item.PSIsContainer) { 0 } else { \$item.Length }
  \$mtime = ([DateTimeOffset]\$item.LastWriteTimeUtc).ToUnixTimeSeconds()
  \$target = if (\$kind -eq 'l' -and \$item.Target) { [string]\$item.Target } else { '' }
  \$childDirectories = 0
  \$childFiles = 0
  if (\$kind -eq 'd') {
    try {
      Get-ChildItem -LiteralPath \$item.FullName -Force -ErrorAction Stop | ForEach-Object {
        if ((\$_.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not \$_.PSIsContainer) { \$childFiles++ } else { \$childDirectories++ }
      }
    } catch {}
  }
  Write-Output ("E`t\$kind`t\$size`t\$mtime`t\$([int]\$item.Attributes)`t\$(B64 \$item.Name)`t\$(B64 \$target)`t\$childDirectories`t\$childFiles")
}
if (\$items.Count -gt $_machineTerminalDirectoryEntryLimit) { Write-Output 'T' }
''';
    return _powerShellCommand(script);
  }
  final changeDirectory = path == null
      ? ''
      : 'cd -- ${_quotePosix(path)} || exit 2\n';
  return '$changeDirectory'
      '__oh_b64() { base64 | tr -d "\\r\\n"; }\n'
      '__oh_pwd=\$(pwd -P) || exit 2\n'
      'printf "P\\t"; printf "%s" "\$__oh_pwd" | __oh_b64; printf "\\n"\n'
      '__oh_count=0\n'
      '__oh_list() {\n'
      'setopt local_options null_glob 2>/dev/null || true\n'
      'for __oh_path in ./* ./.[!.]* ./..?*; do\n'
      '  [ -e "\$__oh_path" ] || [ -L "\$__oh_path" ] || continue\n'
      '  [ "\$__oh_count" -lt $_machineTerminalDirectoryEntryLimit ] || { printf "T\\n"; break; }\n'
      '  __oh_name=\${__oh_path#./}\n'
      'if [ -L "\$__oh_path" ]; then __oh_kind=l; __oh_link=\$(readlink "\$__oh_path" 2>/dev/null || true); '
      'elif [ -d "\$__oh_path" ]; then __oh_kind=d; __oh_link=; '
      'elif [ -f "\$__oh_path" ]; then __oh_kind=f; __oh_link=; '
      'else __oh_kind=o; __oh_link=; fi\n'
      '  __oh_child_dirs=0; __oh_child_files=0\n'
      '  if [ "\$__oh_kind" = d ]; then\n'
      '    for __oh_child in "\$__oh_path"/* "\$__oh_path"/.[!.]* "\$__oh_path"/..?*; do\n'
      '      [ -e "\$__oh_child" ] || [ -L "\$__oh_child" ] || continue\n'
      '      if [ -d "\$__oh_child" ] && [ ! -L "\$__oh_child" ]; then '
      '__oh_child_dirs=\$((__oh_child_dirs + 1)); else '
      '__oh_child_files=\$((__oh_child_files + 1)); fi\n'
      '    done\n'
      '  fi\n'
      '  __oh_meta=\$(stat -c "%s %Y %a" -- "\$__oh_path" 2>/dev/null || stat -f "%z %m %Lp" "\$__oh_path" 2>/dev/null || printf "0 0 -")\n'
      '  __oh_size=\${__oh_meta%% *}; __oh_meta=\${__oh_meta#* }\n'
      '  __oh_mtime=\${__oh_meta%% *}; __oh_mode=\${__oh_meta#* }\n'
      '  printf "E\\t%s\\t%s\\t%s\\t%s\\t" "\$__oh_kind" "\$__oh_size" "\$__oh_mtime" "\$__oh_mode"\n'
      '  printf "%s" "\$__oh_name" | __oh_b64; printf "\\t"\n'
      '  printf "%s" "\$__oh_link" | __oh_b64\n'
      '  printf "\\t%s\\t%s\\n" "\$__oh_child_dirs" "\$__oh_child_files"\n'
      '  __oh_count=\$((__oh_count + 1))\n'
      'done\n'
      '}\n'
      '__oh_list\n'
      'unset -f __oh_list 2>/dev/null || true\n';
}

String _fileDetailsCommand(String path) {
  if (Platform.isWindows) {
    final escapedPath = _escapePowerShell(path);
    final script =
        '''
\$ErrorActionPreference = 'Stop'
function B64([string]\$value) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(\$value)) }
\$item = Get-Item -LiteralPath '$escapedPath' -Force
\$kind = if (\$item.Attributes -band [IO.FileAttributes]::ReparsePoint) { 'l' } elseif (\$item.PSIsContainer) { 'd' } else { 'f' }
\$size = if (\$item.PSIsContainer) { 0 } else { \$item.Length }
\$mtime = ([DateTimeOffset]\$item.LastWriteTimeUtc).ToUnixTimeSeconds()
\$ctime = ([DateTimeOffset]\$item.CreationTimeUtc).ToUnixTimeSeconds()
\$atime = ([DateTimeOffset]\$item.LastAccessTimeUtc).ToUnixTimeSeconds()
\$target = if (\$kind -eq 'l' -and \$item.Target) { [string]\$item.Target } else { '' }
\$childDirectories = 0
\$childFiles = 0
if (\$kind -eq 'd') {
  try {
    Get-ChildItem -LiteralPath \$item.FullName -Force -ErrorAction Stop | ForEach-Object {
      if ((\$_.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not \$_.PSIsContainer) { \$childFiles++ } else { \$childDirectories++ }
    }
  } catch {}
}
Write-Output ("D`t\$kind`t\$(B64 \$item.FullName)`t\$size`t\$mtime`t\$([int]\$item.Attributes)`t\$(B64 \$env:USERNAME)`t`t`t\$(B64 '')`t\$(B64 \$target)`t\$ctime`t\$atime`t\$mtime`t\$childDirectories`t\$childFiles")
''';
    return _powerShellCommand(script);
  }
  final quoted = _quotePosix(path);
  return '__oh_path=$quoted\n'
      '[ -e "\$__oh_path" ] || [ -L "\$__oh_path" ] || exit 2\n'
      '__oh_b64() { base64 | tr -d "\\r\\n"; }\n'
      'if [ -L "\$__oh_path" ]; then __oh_kind=l; __oh_link=\$(readlink "\$__oh_path" 2>/dev/null || true); '
      'elif [ -d "\$__oh_path" ]; then __oh_kind=d; __oh_link=; '
      'elif [ -f "\$__oh_path" ]; then __oh_kind=f; __oh_link=; '
      'else __oh_kind=o; __oh_link=; fi\n'
      '__oh_child_dirs=0; __oh_child_files=0\n'
      'if [ "\$__oh_kind" = d ]; then\n'
      '  for __oh_child in "\$__oh_path"/* "\$__oh_path"/.[!.]* "\$__oh_path"/..?*; do\n'
      '    [ -e "\$__oh_child" ] || [ -L "\$__oh_child" ] || continue\n'
      '    if [ -d "\$__oh_child" ] && [ ! -L "\$__oh_child" ]; then '
      '__oh_child_dirs=\$((__oh_child_dirs + 1)); else '
      '__oh_child_files=\$((__oh_child_files + 1)); fi\n'
      '  done\n'
      'fi\n'
      '__oh_abs=\$(cd -- "\$(dirname -- "\$__oh_path")" && printf "%s/%s" "\$(pwd -P)" "\$(basename -- "\$__oh_path")")\n'
      '__oh_mime=\$(file -b --mime-type -- "\$__oh_path" 2>/dev/null || printf "-")\n'
      'if __oh_meta=\$(stat -c "%s %Y %a %U %G %i %W %X %Z" -- "\$__oh_path" 2>/dev/null); then :; '
      'else __oh_meta=\$(stat -f "%z %m %Lp %Su %Sg %i %B %a %c" "\$__oh_path" 2>/dev/null) || exit 3; fi\n'
      'set -- \$__oh_meta\n'
      'printf "D\\t%s\\t" "\$__oh_kind"; printf "%s" "\$__oh_abs" | __oh_b64\n'
      'printf "\\t%s\\t%s\\t%s\\t" "\$1" "\$2" "\$3"\n'
      'printf "%s" "\$4" | __oh_b64; printf "\\t"; printf "%s" "\$5" | __oh_b64\n'
      'printf "\\t%s\\t" "\$6"; printf "%s" "\$__oh_mime" | __oh_b64; printf "\\t"\n'
      'printf "%s" "\$__oh_link" | __oh_b64\n'
      'printf "\\t%s\\t%s\\t%s\\t%s\\t%s\\n" "\$7" "\$8" "\$9" '
      '"\$__oh_child_dirs" "\$__oh_child_files"\n';
}

String _readChunkCommand(String path, int chunkIndex) {
  if (Platform.isWindows) {
    final offset = chunkIndex * _machineTerminalReadChunkBytes;
    final script =
        '''
\$stream = [IO.File]::OpenRead('${_escapePowerShell(path)}')
try {
  \$stream.Seek($offset, [IO.SeekOrigin]::Begin) | Out-Null
  \$buffer = New-Object byte[] $_machineTerminalReadChunkBytes
  \$count = \$stream.Read(\$buffer, 0, \$buffer.Length)
  \$encoded = if (\$count -gt 0) { [Convert]::ToBase64String(\$buffer, 0, \$count) } else { '' }
  Write-Output ("$_machineTerminalReadChunkBegin`t" + \$encoded + "`t$_machineTerminalReadChunkEnd")
} finally { \$stream.Dispose() }
''';
    return _powerShellCommand(script);
  }
  return 'printf "$_machineTerminalReadChunkBegin\\t"; '
      'dd if=${_quotePosix(path)} bs=$_machineTerminalReadChunkBytes '
      'skip=$chunkIndex count=1 2>/dev/null | base64 | tr -d "\\r\\n"; '
      'printf "\\t$_machineTerminalReadChunkEnd\\n"';
}

String _moveCommand(String sourcePath, String targetPath) {
  if (Platform.isWindows) {
    return _powerShellCommand(
      "Move-Item -LiteralPath '${_escapePowerShell(sourcePath)}' "
      "-Destination '${_escapePowerShell(targetPath)}' -Force",
    );
  }
  return 'mv -f -- ${_quotePosix(sourcePath)} ${_quotePosix(targetPath)}';
}

String _copyCommand(String sourcePath, String targetPath) {
  if (Platform.isWindows) {
    return _powerShellCommand(
      "Copy-Item -LiteralPath '${_escapePowerShell(sourcePath)}' "
      "-Destination '${_escapePowerShell(targetPath)}' -Recurse -Force",
    );
  }
  return 'cp -a -- ${_quotePosix(sourcePath)} ${_quotePosix(targetPath)}';
}

String _deleteCommand(String path) {
  if (Platform.isWindows) {
    return _powerShellCommand(
      "Remove-Item -LiteralPath '${_escapePowerShell(path)}' -Recurse -Force",
    );
  }
  return 'rm -rf -- ${_quotePosix(path)}';
}

String _quotePosix(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

String _escapePowerShell(String value) => value.replaceAll("'", "''");

String _powerShellCommand(String script) {
  final bytes = <int>[];
  for (final codeUnit in script.codeUnits) {
    bytes
      ..add(codeUnit & 0xff)
      ..add((codeUnit >> 8) & 0xff);
  }
  return 'powershell.exe -NoProfile -NonInteractive -EncodedCommand '
      '${base64Encode(bytes)}';
}

final RegExp _machineTerminalReadChunkPattern = RegExp(
  '$_machineTerminalReadChunkBegin\\t([A-Za-z0-9+/=]*)\\t'
  '$_machineTerminalReadChunkEnd',
);
final RegExp _machineTerminalStagedPathPattern = RegExp(
  '$_machineTerminalStagedPathBegin([A-Za-z0-9+/=]+)'
  '$_machineTerminalStagedPathEnd',
);
final RegExp _machineTerminalStagedFilePathPattern = RegExp(
  r'/openhand-command\.[A-Za-z0-9]{6,}$',
);
final RegExp _machineTerminalUnsafePathCharacterPattern = RegExp(
  r'[\x00-\x1F\x7F]',
);
