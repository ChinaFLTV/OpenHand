import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/timer_safety.dart';

/// Harness 提示词上下文读取与工作区扫描共用的安全限制。
class HarnessFileIoLimits {
  HarnessFileIoLimits({
    required this.maxScannedFiles,
    required this.maxTextFiles,
    required this.maxDirectoryEntries,
    required this.maxFileBytes,
    required this.maxTotalBytes,
    required this.totalTimeout,
    required this.operationTimeout,
  }) {
    final positiveIntegers = <String, int>{
      'maxScannedFiles': maxScannedFiles,
      'maxTextFiles': maxTextFiles,
      'maxDirectoryEntries': maxDirectoryEntries,
      'maxFileBytes': maxFileBytes,
      'maxTotalBytes': maxTotalBytes,
    };
    for (final entry in positiveIntegers.entries) {
      if (entry.value < 1) {
        throw ArgumentError.value(entry.value, entry.key, '必须大于零。');
      }
    }
    if (totalTimeout <= Duration.zero) {
      throw ArgumentError.value(totalTimeout, 'totalTimeout', '必须大于零。');
    }
    if (operationTimeout <= Duration.zero) {
      throw ArgumentError.value(operationTimeout, 'operationTimeout', '必须大于零。');
    }
  }

  final int maxScannedFiles;
  final int maxTextFiles;
  final int maxDirectoryEntries;
  final int maxFileBytes;
  final int maxTotalBytes;
  final Duration totalTimeout;
  final Duration operationTimeout;
}

class HarnessTextFileRead {
  const HarnessTextFileRead({required this.text, required this.byteLength});

  final String text;
  final int byteLength;
}

class HarnessFileSnapshot {
  const HarnessFileSnapshot({
    required this.modified,
    required this.size,
    this.content,
  });

  final DateTime modified;
  final int size;
  final String? content;

  HarnessFileSnapshot withContent(String value) =>
      HarnessFileSnapshot(modified: modified, size: size, content: value);
}

/// 仅当 [complete] 为 true 时，快照才可安全比较。
class HarnessDirectorySnapshot {
  HarnessDirectorySnapshot({
    required Map<String, HarnessFileSnapshot> files,
    required this.complete,
  }) : files = Map<String, HarnessFileSnapshot>.unmodifiable(files);

  HarnessDirectorySnapshot.incomplete()
    : files = const <String, HarnessFileSnapshot>{},
      complete = false;

  final Map<String, HarnessFileSnapshot> files;
  final bool complete;
}

class HarnessFileScanResult {
  HarnessFileScanResult({required List<File> files, required this.complete})
    : files = List<File>.unmodifiable(files);

  final List<File> files;
  final bool complete;
}

/// 在统一总预算内执行 Harness 异步文件系统操作。
///
/// 实例按短生命周期串行使用；目录枚举、文本解码、保留内容与耗时均有上限，
/// 避免项目路径阻塞或耗尽 UI isolate。
class HarnessBoundedFileIo {
  HarnessBoundedFileIo(this.limits) : _stopwatch = Stopwatch()..start();

  final HarnessFileIoLimits limits;
  final Stopwatch _stopwatch;

  int _filesRead = 0;
  int _bytesRead = 0;
  int _directoryEntriesVisited = 0;

  bool get isExpired => _remainingTime <= Duration.zero;

  /// 读取单个 UTF-8 文件，保留内容不超过单文件及总字节预算。
  /// 无效 UTF-8 或不完整读取均视为内容不可用。
  Future<HarnessTextFileRead?> readText(
    File file, {
    int? knownSize,
    int? maxBytes,
  }) async {
    if (_filesRead >= limits.maxTextFiles || isExpired) return null;

    final aggregateBytesLeft = limits.maxTotalBytes - _bytesRead;
    final requestedLimit = maxBytes ?? limits.maxFileBytes;
    final byteLimit = math.min(
      limits.maxFileBytes,
      math.min(aggregateBytesLeft, requestedLimit),
    );
    if (byteLimit <= 0) return null;

    _filesRead++;
    if (knownSize != null && (knownSize < 0 || knownSize > byteLimit)) {
      return null;
    }

    final timeout = _nextOperationTimeout();
    if (timeout == null) return null;
    final result = await _readUtf8Stream(file, byteLimit, timeout);
    if (result != null) {
      _bytesRead += result.byteLength;
    }
    return result;
  }

  /// 枚举文件且不递归进入已忽略目录；触及数量、时间或文件系统边界时，
  /// [complete] 为 false。
  Future<HarnessFileScanResult> scanFiles(
    Directory root, {
    bool recursive = false,
    Set<String> ignoredNames = const <String>{},
    int? maxFiles,
  }) async {
    final effectiveMaxFiles = math.min(
      limits.maxScannedFiles,
      maxFiles ?? limits.maxScannedFiles,
    );
    if (effectiveMaxFiles <= 0 || isExpired) {
      return HarnessFileScanResult(files: const <File>[], complete: false);
    }

    final files = <File>[];
    final pendingDirectories = Queue<Directory>()..add(root);
    var complete = true;

    scan:
    while (pendingDirectories.isNotEmpty) {
      final entriesLeft = limits.maxDirectoryEntries - _directoryEntriesVisited;
      final timeout = _nextOperationTimeout();
      if (entriesLeft <= 0 || timeout == null) {
        complete = false;
        break;
      }

      final directory = pendingDirectories.removeFirst();
      final batch = await _listDirectory(
        directory,
        maxEntries: entriesLeft,
        timeout: timeout,
      );
      _directoryEntriesVisited += batch.entries.length;
      if (!batch.complete) complete = false;

      for (final entity in batch.entries) {
        if (ignoredNames.contains(p.basename(entity.path))) continue;
        if (entity is File) {
          if (files.length >= effectiveMaxFiles) {
            complete = false;
            break scan;
          }
          files.add(entity);
        } else if (recursive && entity is Directory) {
          pendingDirectories.add(entity);
        }
      }

      if (!batch.complete) break;
    }

    return HarnessFileScanResult(files: files, complete: complete);
  }

  Future<String> readLexicographicallyLatestText(
    Directory directory, {
    int? maxBytes,
  }) async {
    final scan = await scanFiles(directory);
    if (!scan.complete || scan.files.isEmpty) return '';

    var latest = scan.files.first;
    for (final file in scan.files.skip(1)) {
      if (file.path.compareTo(latest.path) > 0) latest = file;
    }
    return (await readText(latest, maxBytes: maxBytes))?.text ?? '';
  }

  /// 按枚举顺序读取直接子文件并拼接，同时限制包含分隔符的局部输出总量。
  Future<String> readJoinedTextFiles(
    Directory directory, {
    required String separator,
    required int maxJoinedBytes,
    int? maxFiles,
  }) async {
    if (maxJoinedBytes <= 0 || isExpired) return '';

    final scan = await scanFiles(directory, maxFiles: maxFiles);
    final separatorBytes = utf8.encode(separator).length;
    final buffer = StringBuffer();
    var joinedBytes = 0;
    var hasFile = false;

    for (final file in scan.files) {
      final prefixBytes = hasFile ? separatorBytes : 0;
      final bytesLeft = maxJoinedBytes - joinedBytes - prefixBytes;
      if (bytesLeft < 0) break;

      final read = await readText(file, maxBytes: bytesLeft);
      if (read == null) continue;
      if (hasFile) {
        buffer.write(separator);
        joinedBytes += separatorBytes;
      }
      buffer.write(read.text);
      joinedBytes += read.byteLength;
      hasFile = true;
    }
    return buffer.toString();
  }

  /// 为每个已枚举文件采集有界元数据，再用剩余时间和字节保留差异比较所需的
  /// UTF-8 内容；内容预算耗尽不会使元数据快照失效。
  Future<HarnessDirectorySnapshot> snapshotDirectory(
    Directory root, {
    Set<String> ignoredNames = const <String>{},
  }) async {
    final scan = await scanFiles(
      root,
      recursive: true,
      ignoredNames: ignoredNames,
    );
    if (!scan.complete) return HarnessDirectorySnapshot.incomplete();

    final snapshots = <String, HarnessFileSnapshot>{};
    final contentCandidates = <({File file, String relativePath, int size})>[];

    for (final file in scan.files) {
      final timeout = _nextOperationTimeout();
      if (timeout == null) return HarnessDirectorySnapshot.incomplete();

      try {
        final stat = await file.stat().timeout(timeout);
        if (stat.type != FileSystemEntityType.file) {
          return HarnessDirectorySnapshot.incomplete();
        }
        final relativePath = p.relative(file.path, from: root.path);
        snapshots[relativePath] = HarnessFileSnapshot(
          modified: stat.modified,
          size: stat.size,
        );
        if (stat.size <= limits.maxFileBytes) {
          contentCandidates.add((
            file: file,
            relativePath: relativePath,
            size: stat.size,
          ));
        }
      } on Object {
        return HarnessDirectorySnapshot.incomplete();
      }
    }

    for (final candidate in contentCandidates) {
      if (isExpired || _bytesRead >= limits.maxTotalBytes) break;
      final read = await readText(candidate.file, knownSize: candidate.size);
      if (read == null) continue;
      if (read.byteLength != candidate.size) {
        // 文件在元数据采集与内容保留之间发生变化，混合代际快照可能误报差异。
        return HarnessDirectorySnapshot.incomplete();
      }
      snapshots[candidate.relativePath] = snapshots[candidate.relativePath]!
          .withContent(read.text);
    }

    return HarnessDirectorySnapshot(files: snapshots, complete: true);
  }

  Duration get _remainingTime {
    final microseconds =
        limits.totalTimeout.inMicroseconds - _stopwatch.elapsedMicroseconds;
    return Duration(microseconds: math.max(0, microseconds));
  }

  Duration? _nextOperationTimeout() {
    final remaining = _remainingTime;
    if (remaining <= Duration.zero) return null;
    return remaining < limits.operationTimeout
        ? remaining
        : limits.operationTimeout;
  }

  Future<HarnessTextFileRead?> _readUtf8Stream(
    File file,
    int byteLimit,
    Duration timeout,
  ) async {
    try {
      final bytes = await readBoundedFileBytes(
        file,
        maxBytes: byteLimit,
        idleTimeout: timeout,
        totalTimeout: timeout,
      );
      return HarnessTextFileRead(
        text: utf8.decode(bytes),
        byteLength: bytes.length,
      );
    } on Object {
      return null;
    }
  }

  Future<_HarnessDirectoryEntries> _listDirectory(
    Directory directory, {
    required int maxEntries,
    required Duration timeout,
  }) {
    final completer = Completer<_HarnessDirectoryEntries>();
    final entries = <FileSystemEntity>[];
    var settled = false;
    Timer? timer;
    StreamSubscription<FileSystemEntity>? subscription;

    void cancelSubscription() {
      final current = subscription;
      if (current == null) return;
      try {
        unawaited(
          current
              .cancel()
              .timeout(timeout, onTimeout: () {})
              .catchError((Object _, StackTrace _) {}),
        );
      } on Object {
        // 枚举结果已经确定，取消仅作为尽力清理。
      }
    }

    void settle(bool complete, {bool cancel = false}) {
      if (settled) return;
      settled = true;
      timer?.cancel();
      if (cancel) cancelSubscription();
      completer.complete(
        _HarnessDirectoryEntries(entries: entries, complete: complete),
      );
    }

    try {
      final createdSubscription = directory
          .list(followLinks: false)
          .listen(
            (entity) {
              if (settled) return;
              if (entries.length >= maxEntries) {
                settle(false, cancel: true);
                return;
              }
              entries.add(entity);
            },
            onError: (Object _, StackTrace _) => settle(false, cancel: true),
            onDone: () => settle(true),
            cancelOnError: true,
          );
      subscription = createdSubscription;
      if (settled) {
        cancelSubscription();
      } else {
        timer = startSafeTimer(timeout, () => settle(false, cancel: true));
      }
    } on Object {
      settle(false, cancel: true);
    }
    return completer.future;
  }
}

class _HarnessDirectoryEntries {
  const _HarnessDirectoryEntries({
    required this.entries,
    required this.complete,
  });

  final List<FileSystemEntity> entries;
  final bool complete;
}
