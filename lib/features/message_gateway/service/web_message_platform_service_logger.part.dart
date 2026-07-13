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

  static const int _maxExportFiles = 16;
  static const int _maxDirectoryEntries = 1024;
  static const int _maxExportBytesPerFile = 8 * 1024 * 1024;
  static const int _maxExportBundleBytes = 32 * 1024 * 1024;
  static const Duration _exportReadIdleTimeout = Duration(seconds: 3);
  static const Duration _exportReadTotalTimeout = Duration(seconds: 10);

  String get filePath => p.join(directoryPath, 'web-platform.log');

  int get currentSizeBytes {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return 0;
      return file.lengthSync();
    } catch (error, stack) {
      silentLog(
        'web_message_platform_logger',
        'read current log size',
        error,
        stack,
      );
      return 0;
    }
  }

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
      await File(
        filePath,
      ).writeAsString('${entry.toLogLine()}\n', mode: FileMode.append);
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
    final files =
        (await listDirectoryBounded(dir, maxEntries: _maxDirectoryEntries))
            .entries
            .whereType<File>()
            .where((item) => p.basename(item.path).startsWith('web-platform'))
            .toList(growable: false)
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );

    Future<void> deleteFile(File file) async {
      try {
        final stat = await file.stat();
        await file.delete();
        stats += _CleanupStats(deletedFiles: 1, bytesFreed: stat.size);
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
    for (final file in files) {
      if (p.equals(file.path, filePath)) continue;
      if (file.statSync().modified.isBefore(cutoff)) {
        await deleteFile(file);
        deleted.add(file.path);
      }
    }
    final remaining = files
        .where((file) => !deleted.contains(file.path))
        .toList(growable: false);
    for (final old in remaining.skip(config.maxFiles)) {
      if (p.equals(old.path, filePath)) continue;
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
    final files =
        (await listDirectoryBounded(dir, maxEntries: _maxDirectoryEntries))
            .entries
            .whereType<File>()
            .where((item) => p.basename(item.path).startsWith('web-platform'))
            .toList(growable: false)
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
    final items = <Map<String, Object?>>[];
    var remainingBytes = _maxExportBundleBytes;
    for (final file in files) {
      if (items.length >= _maxExportFiles || remainingBytes <= 0) break;
      try {
        final stat = await file.stat();
        final readLimit = math.min(_maxExportBytesPerFile, remainingBytes);
        final bytes = await _readLogTail(
          file,
          fileSize: stat.size,
          maxBytes: readLimit,
        );
        remainingBytes -= bytes.length;
        items.add(<String, Object?>{
          'name': p.basename(file.path),
          'size': stat.size,
          'exported_size': bytes.length,
          'truncated': stat.size > bytes.length,
          'modified_at': stat.modified.toUtc().toIso8601String(),
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
    if (!await file.exists()) return;
    final stat = await file.stat();
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
    final logs =
        (await listDirectoryBounded(
              Directory(directoryPath),
              maxEntries: _maxDirectoryEntries,
            )).entries
            .whereType<File>()
            .where((item) => p.basename(item.path).startsWith('web-platform'))
            .toList(growable: false)
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
    for (final old in logs.skip(config.maxFiles)) {
      try {
        await old.delete();
      } catch (error, stack) {
        silentLog(
          'web_gateway_logger',
          'trim rotated ${old.path}',
          error,
          stack,
        );
      }
    }
  }
}
