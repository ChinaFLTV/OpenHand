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
/// - 所有 IO 异常通过 `silentLog` 静默——日志系统自身崩溃不能拖垮 Web 服务。
class _WebGatewayRotatingLogger {
  _WebGatewayRotatingLogger({String? logsDirectoryPath})
    : directoryPath = p.join(
        logsDirectoryPath ?? OpenHandPaths.defaultLogsDirectoryPath(),
        'message_gateway',
      );

  final String directoryPath;
  final SerialTaskQueue _operations = SerialTaskQueue();
  int _currentSizeBytes = 0;

  static const int _maxExportFiles = 16;
  static const int _maxDirectoryEntries = 1024;
  static const int _maxExportBytesPerFile = 8 * 1024 * 1024;
  static const int _maxExportBundleBytes = 32 * 1024 * 1024;
  static const Duration _exportReadIdleTimeout = Duration(seconds: 3);
  static const Duration _exportReadTotalTimeout = Duration(seconds: 10);
  static const Duration _metadataTimeout = Duration(seconds: 2);
  static const Duration _metadataTotalTimeout = Duration(seconds: 10);

  String get filePath => p.join(directoryPath, 'web-platform.log');

  int get currentSizeBytes => _currentSizeBytes;

  Future<void> write(WebGatewayLogEntry entry, WebGatewayLogConfig config) {
    return _operations.enqueue(() => _write(entry, config));
  }

  Future<void> _write(
    WebGatewayLogEntry entry,
    WebGatewayLogConfig config,
  ) async {
    try {
      final dir = Directory(directoryPath);
      await dir.create(recursive: true);
      await _rotateIfNeeded(config);
      final line = '${entry.toLogLine()}\n';
      await File(filePath).writeAsString(line, mode: FileMode.append);
      _currentSizeBytes += utf8.encode(line).length;
    } catch (error, stack) {
      silentLog('web_gateway_logger', 'write', error, stack);
    }
  }

  Future<_CleanupStats> clear() {
    return _operations.enqueue(_clear);
  }

  Future<_CleanupStats> _clear() async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return const _CleanupStats();
    var stats = const _CleanupStats();
    final files =
        (await listDirectoryBounded(dir, maxEntries: _maxDirectoryEntries))
            .entries
            .whereType<File>()
            .where((item) => p.basename(item.path).startsWith('web-platform'));
    for (final file in files) {
      try {
        final stat = await file.stat();
        await file.delete();
        if (p.equals(file.path, filePath)) {
          _currentSizeBytes = 0;
        }
        stats += _CleanupStats(deletedFiles: 1, bytesFreed: stat.size);
      } catch (error, stack) {
        silentLog(
          'web_gateway_logger',
          'clear delete ${file.path}',
          error,
          stack,
        );
      }
    }
    return stats;
  }

  Future<_CleanupStats> prune(WebGatewayLogConfig config) {
    return _operations.enqueue(() => _prune(config));
  }

  Future<_CleanupStats> _prune(WebGatewayLogConfig config) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return const _CleanupStats();
    final cutoff = DateTime.now().subtract(Duration(days: config.rotationDays));
    var stats = const _CleanupStats();
    final files = await _logFilesNewestFirst(dir);

    Future<void> deleteFile(_LogFileSnapshot item) async {
      final file = item.file;
      try {
        await file.delete();
        stats += _CleanupStats(deletedFiles: 1, bytesFreed: item.stat.size);
      } catch (error, stack) {
        silentLog(
          'web_gateway_logger',
          'prune delete ${file.path}',
          error,
          stack,
        );
      }
    }

    final deleted = <String>{};
    for (final item in files) {
      final file = item.file;
      if (p.equals(file.path, filePath)) continue;
      if (item.stat.modified.isBefore(cutoff)) {
        await deleteFile(item);
        deleted.add(file.path);
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
    return _operations.enqueue(_readBundle);
  }

  Future<List<Map<String, Object?>>> _readBundle() async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return const <Map<String, Object?>>[];
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
        silentLog(
          'web_gateway_logger',
          'read bundle ${file.path}',
          error,
          stack,
        );
      }
    }
    return items;
  }

  Future<String> readCurrentLogText() {
    return _operations.enqueue(_readCurrentLogText);
  }

  Future<String> _readCurrentLogText() async {
    final file = File(filePath);
    if (!await file.exists()) return '';
    final stat = await file.stat();
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
    if (!await file.exists()) {
      _currentSizeBytes = 0;
      return;
    }
    final stat = await file.stat();
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
    await file.rename(p.join(directoryPath, 'web-platform-$stamp.log'));
    _currentSizeBytes = 0;
    final logs = await _logFilesNewestFirst(Directory(directoryPath));
    for (final old in logs.skip(config.maxFiles)) {
      try {
        await old.file.delete();
      } catch (error, stack) {
        silentLog(
          'web_gateway_logger',
          'trim rotated ${old.file.path}',
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
