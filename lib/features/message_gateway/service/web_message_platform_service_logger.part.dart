part of 'web_message_platform_service.dart';

/// Web 服务文件清理（日志/上传缓存）累计统计。
class _CleanupStats {
  const _CleanupStats({
    this.deletedFiles = 0,
    this.deletedDirectories = 0,
    this.bytesFreed = 0,
  });

  final int deletedFiles;
  final int deletedDirectories;
  final int bytesFreed;

  _CleanupStats copyWith({
    int? deletedFiles,
    int? deletedDirectories,
    int? bytesFreed,
  }) {
    return _CleanupStats(
      deletedFiles: deletedFiles ?? this.deletedFiles,
      deletedDirectories: deletedDirectories ?? this.deletedDirectories,
      bytesFreed: bytesFreed ?? this.bytesFreed,
    );
  }

  _CleanupStats operator +(_CleanupStats other) {
    return _CleanupStats(
      deletedFiles: deletedFiles + other.deletedFiles,
      deletedDirectories: deletedDirectories + other.deletedDirectories,
      bytesFreed: bytesFreed + other.bytesFreed,
    );
  }
}

typedef _LogFileSnapshot = ({File file, FileStat stat});

/// 文件日志轮转 + 持久化 + 离线读取。
///
/// 行为：
/// - `write` 在 append 前先调用 `_rotateIfNeeded` 检查文件大小/年龄；超过阈值
///   的当前日志会被改名为带时间戳的归档文件，再创建新空文件继续写。
/// - `clear` 删除目录下所有 `web-platform*` 文件；`prune` 仅删除超期或超出
///   `maxFiles` 上限的归档文件，当前正在写入的 `web-platform.log` 不动。
/// - `readBundle` 把所有日志文件按修改时间倒序读出，供离线导出/Web 端 ops 拉取。
/// - 文件写入有条数与字节双上限；慢盘时拒绝新增写入并在下一条落盘日志中
///   汇总丢弃数量，避免异步任务链无限增长。
/// - 单次文件变更超时后停止全部磁盘入口，避免迟到操作与后续读写交错。
/// - 所有 IO 异常通过 `silentLog` 记录，日志系统自身故障不拖垮 Web 服务。
class _WebGatewayRotatingLogger {
  _WebGatewayRotatingLogger({String? logsDirectoryPath})
    : directoryPath = p.join(
        logsDirectoryPath ?? OpenHandPaths.defaultLogsDirectoryPath(),
        'message_gateway',
      );

  final String directoryPath;
  final SerialTaskQueue _operations = SerialTaskQueue();
  int _currentSizeBytes = 0;
  int _pendingWriteCount = 0;
  int _pendingWriteBytes = 0;
  int _droppedWriteCount = 0;
  int _unreportedDroppedWrites = 0;
  bool _ioTimedOut = false;
  bool _closing = false;
  Future<void>? _closeFuture;
  WebGatewayLogConfig _lastConfig = const WebGatewayLogConfig();

  static const int _maxExportFiles = 16;
  static const int _maxDirectoryEntries = 1024;
  static const int _maxExportBytesPerFile = 8 * kBytesPerMiB;
  static const int _maxExportBundleBytes = 32 * kBytesPerMiB;
  static const Duration _exportReadIdleTimeout = Duration(seconds: 3);
  static const Duration _exportReadTotalTimeout = Duration(seconds: 10);
  static const Duration _metadataTimeout = Duration(seconds: 2);
  static const Duration _metadataTotalTimeout = Duration(seconds: 10);
  static const Duration _writeIoTimeout = Duration(seconds: 3);
  static const int _maxPendingWrites = 1024;
  static const int _maxPendingWriteBytes = 4 * kBytesPerMiB;
  static const Duration _closeTimeout = Duration(seconds: 5);
  static const String _droppedBeforeKey = 'file_logger_dropped_before';
  static const String _diskOperationStoppedMessage = '文件日志器发生 I/O 超时，磁盘操作已停止。';

  String get filePath => p.join(directoryPath, 'web-platform.log');

  int get currentSizeBytes => _currentSizeBytes;
  int get pendingWriteCount => _pendingWriteCount;
  int get pendingWriteBytes => _pendingWriteBytes;
  int get droppedWriteCount => _droppedWriteCount;

  Future<void> write(WebGatewayLogEntry entry, WebGatewayLogConfig config) {
    _lastConfig = config;
    if (_closing || _ioTimedOut) {
      _recordDroppedWrite();
      return Future<void>.value();
    }
    if (_pendingWriteCount >= _maxPendingWrites ||
        _pendingWriteBytes >= _maxPendingWriteBytes) {
      _recordDroppedWrite();
      return Future<void>.value();
    }
    Uint8List bytes;
    try {
      bytes = _encodeEntry(entry);
    } catch (error, stack) {
      _recordDroppedWrite();
      silentLog('web_gateway_logger', '编码日志条目', error, stack);
      return Future<void>.value();
    }
    if (!_canAccept(bytes.length)) {
      _recordDroppedWrite();
      return Future<void>.value();
    }
    var reservedDroppedWrites = 0;
    if (_unreportedDroppedWrites > 0) {
      final annotated = _encodeEntry(
        entry,
        droppedBefore: _unreportedDroppedWrites,
      );
      if (_canAccept(annotated.length)) {
        bytes = annotated;
        reservedDroppedWrites = _unreportedDroppedWrites;
        _unreportedDroppedWrites = 0;
      }
    }
    _pendingWriteCount++;
    _pendingWriteBytes += bytes.length;
    final byteCount = bytes.length;
    return _operations
        .enqueue(() => _writeBytes(bytes, config))
        .then<void>(
          (written) {
            if (!written) _recordDroppedWrite(reservedDroppedWrites);
          },
          onError: (Object error, StackTrace stack) {
            _recordDroppedWrite(reservedDroppedWrites);
            silentLog('web_gateway_logger', '提交日志写入任务', error, stack);
          },
        )
        .whenComplete(() {
          _pendingWriteCount--;
          _pendingWriteBytes -= byteCount;
        });
  }

  Future<bool> _writeBytes(Uint8List bytes, WebGatewayLogConfig config) async {
    if (_ioTimedOut) return false;
    try {
      final dir = Directory(directoryPath);
      await dir.create(recursive: true).timeout(_writeIoTimeout);
      await _rotateIfNeeded(config);
      final output = await openBoundedRandomAccessFileLease(
        File(filePath),
        mode: FileMode.append,
        timeout: _writeIoTimeout,
      );
      try {
        await output.run<void>((file) async {
          await file.writeFrom(bytes);
        }, timeout: _writeIoTimeout);
        await output.close(timeout: _writeIoTimeout);
      } finally {
        await output.cleanup();
      }
      _currentSizeBytes += bytes.length;
      return true;
    } on TimeoutException catch (error, stack) {
      _markIoTimedOut('写入日志文件超时，已停止后续磁盘操作', error, stack);
      return false;
    } catch (error, stack) {
      silentLog('web_gateway_logger', '写入日志文件', error, stack);
      return false;
    }
  }

  bool _canAccept(int bytes) {
    return bytes <= _maxPendingWriteBytes &&
        _pendingWriteCount < _maxPendingWrites &&
        _pendingWriteBytes + bytes <= _maxPendingWriteBytes;
  }

  Uint8List _encodeEntry(WebGatewayLogEntry entry, {int droppedBefore = 0}) {
    final json = entry.toJson();
    if (droppedBefore > 0) {
      json['data'] = <String, Object?>{
        ...stringKeyedMapFromValue(json['data']),
        _droppedBeforeKey: droppedBefore,
      };
    }
    return Uint8List.fromList(utf8.encode('${jsonEncode(json)}\n'));
  }

  void _recordDroppedWrite([int reservedDroppedWrites = 0]) {
    _droppedWriteCount++;
    _unreportedDroppedWrites += reservedDroppedWrites + 1;
  }

  Future<void> close() {
    final active = _closeFuture;
    if (active != null) return active;
    _closing = true;
    final drain = _operations.enqueue(_flushDroppedWrites);
    final close = runAsyncCleanupBounded(
      () => drain,
      timeout: _closeTimeout,
      onError: (error, stack) =>
          silentLog('web_gateway_logger', '关闭文件日志器', error, stack),
    ).then<void>((_) {});
    _closeFuture = close;
    return close;
  }

  Future<void> _flushDroppedWrites() async {
    if (_ioTimedOut) return;
    final dropped = _unreportedDroppedWrites;
    if (dropped <= 0) return;
    _unreportedDroppedWrites = 0;
    final summary = WebGatewayLogEntry(
      id: 0,
      timestamp: DateTime.now().toUtc(),
      level: WebGatewayLogLevel.warn,
      tag: 'LOGGER',
      message: '文件日志写入达到容量上限',
      data: <String, Object?>{'dropped_count': dropped},
    );
    if (!await _writeBytes(_encodeEntry(summary), _lastConfig)) {
      _unreportedDroppedWrites += dropped;
    }
  }

  Future<_CleanupStats> clear() {
    return _enqueueDiskOperation(_clear);
  }

  Future<_CleanupStats> _clear() async {
    final dir = Directory(directoryPath);
    if (!await dir.exists().timeout(_metadataTimeout)) {
      return const _CleanupStats();
    }
    var stats = const _CleanupStats();
    final files =
        (await listDirectoryBounded(dir, maxEntries: _maxDirectoryEntries))
            .entries
            .whereType<File>()
            .where((item) => p.basename(item.path).startsWith('web-platform'));
    for (final file in files) {
      try {
        final stat = await file.stat().timeout(_metadataTimeout);
        await file.delete().timeout(_writeIoTimeout);
        if (p.equals(file.path, filePath)) {
          _currentSizeBytes = 0;
        }
        stats += _CleanupStats(deletedFiles: 1, bytesFreed: stat.size);
      } on TimeoutException catch (error, stack) {
        _markIoTimedOut('清空日志文件超时，已停止后续磁盘操作', error, stack);
        break;
      } catch (error, stack) {
        silentLog('web_gateway_logger', '清空时删除文件：${file.path}', error, stack);
      }
    }
    return stats;
  }

  Future<_CleanupStats> prune(WebGatewayLogConfig config) {
    return _enqueueDiskOperation(() => _prune(config));
  }

  Future<_CleanupStats> _prune(WebGatewayLogConfig config) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists().timeout(_metadataTimeout)) {
      return const _CleanupStats();
    }
    final cutoff = DateTime.now().subtract(Duration(days: config.rotationDays));
    var stats = const _CleanupStats();
    final files = await _logFilesNewestFirst(dir);

    Future<bool> deleteFile(_LogFileSnapshot item) async {
      final file = item.file;
      try {
        await file.delete().timeout(_writeIoTimeout);
        stats += _CleanupStats(deletedFiles: 1, bytesFreed: item.stat.size);
        return true;
      } on TimeoutException catch (error, stack) {
        _markIoTimedOut('裁剪日志文件超时，已停止后续磁盘操作', error, stack);
        rethrow;
      } catch (error, stack) {
        silentLog('web_gateway_logger', '裁剪时删除文件：${file.path}', error, stack);
        return false;
      }
    }

    final deleted = <String>{};
    for (final item in files) {
      final file = item.file;
      if (p.equals(file.path, filePath)) continue;
      if (item.stat.modified.isBefore(cutoff)) {
        if (await deleteFile(item)) {
          deleted.add(file.path);
        }
      }
    }
    final remaining = files
        .where((item) => !deleted.contains(item.file.path))
        .toList(growable: false);
    for (final old in remaining.skip(config.maxFiles)) {
      if (p.equals(old.file.path, filePath)) continue;
      await deleteFile(old);
    }
    return stats;
  }

  Future<List<Map<String, Object?>>> readBundle() {
    return _enqueueDiskOperation(_readBundle);
  }

  Future<List<Map<String, Object?>>> _readBundle() async {
    final dir = Directory(directoryPath);
    if (!await dir.exists().timeout(_metadataTimeout)) {
      return const <Map<String, Object?>>[];
    }
    final files = await _logFilesNewestFirst(dir);
    final items = <Map<String, Object?>>[];
    var remainingBytes = _maxExportBundleBytes;
    for (final item in files) {
      if (items.length >= _maxExportFiles || remainingBytes <= 0) break;
      final file = item.file;
      try {
        final readLimit = math.min(_maxExportBytesPerFile, remainingBytes);
        final bytes = await _readLogTail(
          file,
          fileSize: item.stat.size,
          maxBytes: readLimit,
        );
        if (p.equals(file.path, filePath)) {
          _currentSizeBytes = item.stat.size;
        }
        remainingBytes -= bytes.length;
        items.add(<String, Object?>{
          'name': p.basename(file.path),
          'size': item.stat.size,
          'exported_size': bytes.length,
          'truncated': item.stat.size > bytes.length,
          'modified_at': item.stat.modified.toUtc().toIso8601String(),
          'content': utf8.decode(bytes, allowMalformed: true),
        });
      } catch (error, stack) {
        silentLog('web_gateway_logger', '读取日志包：${file.path}', error, stack);
      }
    }
    return items;
  }

  Future<String> readCurrentLogText() {
    return _enqueueDiskOperation(_readCurrentLogText);
  }

  Future<T> _enqueueDiskOperation<T>(Future<T> Function() operation) {
    if (_closing) {
      return Future<T>.error(StateError('文件日志器已关闭。'));
    }
    if (_ioTimedOut) {
      return Future<T>.error(StateError(_diskOperationStoppedMessage));
    }
    return _operations.enqueue(() {
      if (_ioTimedOut) {
        throw StateError(_diskOperationStoppedMessage);
      }
      return operation();
    });
  }

  void _markIoTimedOut(String action, Object error, StackTrace stack) {
    _ioTimedOut = true;
    silentLog('web_gateway_logger', action, error, stack);
  }

  Future<String> _readCurrentLogText() async {
    final file = File(filePath);
    if (!await file.exists().timeout(_metadataTimeout)) return '';
    final stat = await file.stat().timeout(_metadataTimeout);
    _currentSizeBytes = stat.size;
    final bytes = await _readLogTail(
      file,
      fileSize: stat.size,
      maxBytes: _maxExportBytesPerFile,
    );
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<Uint8List> _readLogTail(
    File file, {
    required int fileSize,
    required int maxBytes,
  }) {
    final start = math.max(0, fileSize - maxBytes);
    return readBoundedByteStream(
      file.openRead(start, fileSize),
      maxBytes: maxBytes,
      idleTimeout: _exportReadIdleTimeout,
      totalTimeout: _exportReadTotalTimeout,
    );
  }

  Future<void> _rotateIfNeeded(WebGatewayLogConfig config) async {
    final file = File(filePath);
    if (!await file.exists().timeout(_writeIoTimeout)) {
      _currentSizeBytes = 0;
      return;
    }
    final stat = await file.stat().timeout(_writeIoTimeout);
    _currentSizeBytes = stat.size;
    final tooLarge = stat.size >= config.fileMaxBytes;
    final tooOld =
        DateTime.now().difference(stat.modified).inDays >= config.rotationDays;
    if (!tooLarge && !tooOld) return;
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    await file
        .rename(p.join(directoryPath, 'web-platform-$stamp.log'))
        .timeout(_writeIoTimeout);
    _currentSizeBytes = 0;
    final logs = await _logFilesNewestFirst(Directory(directoryPath));
    for (final old in logs.skip(config.maxFiles)) {
      try {
        await old.file.delete().timeout(_writeIoTimeout);
      } on TimeoutException {
        rethrow;
      } catch (error, stack) {
        silentLog(
          'web_gateway_logger',
          '清理轮转日志：${old.file.path}',
          error,
          stack,
        );
      }
    }
  }

  Future<List<_LogFileSnapshot>> _logFilesNewestFirst(
    Directory directory,
  ) async {
    final files =
        (await listDirectoryBounded(
          directory,
          maxEntries: _maxDirectoryEntries,
        )).entries.whereType<File>().where(
          (item) => p.basename(item.path).startsWith('web-platform'),
        );
    final snapshots = <_LogFileSnapshot>[];
    final stopwatch = Stopwatch()..start();
    try {
      for (final file in files) {
        final remaining = _metadataTotalTimeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) break;
        final timeout = remaining < _metadataTimeout
            ? remaining
            : _metadataTimeout;
        try {
          snapshots.add((file: file, stat: await file.stat().timeout(timeout)));
        } on TimeoutException {
          break;
        } on FileSystemException {
          continue;
        }
      }
    } finally {
      stopwatch.stop();
    }
    snapshots.sort(
      (left, right) => right.stat.modified.compareTo(left.stat.modified),
    );
    return snapshots;
  }
}
