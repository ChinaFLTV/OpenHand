import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 文件追踪器服务，用于检测脏写（dirty write）
///
/// 核心机制：
/// 1. Read 时记录文件的 modTime、size 与可用内容指纹
/// 2. Edit/Write 前重新采样当前文件快照
/// 3. 优先用内容指纹识别真实变化，避免时间戳抖动误报或容差漏报
class AiFileTrackerService {
  AiFileTrackerService();

  static const Duration _timestampTolerance = Duration(seconds: 2);
  static const int _maxFingerprintBytes = 4 * 1024 * 1024;

  /// 文件路径 → 读取时的文件快照
  final Map<String, _TrackedFileSnapshot> _readSnapshots =
      <String, _TrackedFileSnapshot>{};

  /// 文件路径 → 最近一次 Read 工具返回的范围快照。
  ///
  /// 仅用于重复 Read 去重；Edit/Write 后会清除，避免把模型指向旧的
  /// Read tool_result。
  final Map<String, _TrackedReadResult> _readResultSnapshots =
      <String, _TrackedReadResult>{};

  /// 记录文件读取快照
  ///
  /// 在 Read 工具执行成功后调用
  Future<void> recordFileRead(String filePath) async {
    final normalizedPath = p.normalize(filePath);
    final file = File(normalizedPath);
    if (!await file.exists()) return;
    _readSnapshots[normalizedPath] = await _snapshotFile(file);
    _readResultSnapshots.remove(normalizedPath);
  }

  /// 记录 Read 工具成功返回的文件范围快照。
  Future<void> recordReadResult({
    required String filePath,
    required int offset,
    required int limit,
  }) async {
    final normalizedPath = p.normalize(filePath);
    final file = File(normalizedPath);
    if (!await file.exists()) return;
    final snapshot = await _snapshotFile(file);
    _readSnapshots[normalizedPath] = snapshot;
    _readResultSnapshots[normalizedPath] = _TrackedReadResult(
      offset: offset,
      limit: limit,
      snapshot: snapshot,
    );
  }

  /// 如果同一 Read 范围自上次读取后未变化，返回 true。
  Future<bool> isReadResultUnchanged({
    required String filePath,
    required int offset,
    required int limit,
  }) async {
    final normalizedPath = p.normalize(filePath);
    final previousRead = _readResultSnapshots[normalizedPath];
    if (previousRead == null ||
        previousRead.offset != offset ||
        previousRead.limit != limit) {
      return false;
    }
    final file = File(normalizedPath);
    if (!await file.exists()) return false;
    final current = await _snapshotFile(file);
    return previousRead.snapshot.hasSameContentAs(current);
  }

  /// 批量记录文件读取快照
  Future<void> recordFilesRead(Iterable<String> filePaths) async {
    for (final path in filePaths) {
      await recordFileRead(path);
    }
  }

  /// 检查文件是否可以安全写入（未被外部修改）
  ///
  /// 返回值：
  /// - null: 可以安全写入
  /// - String: 错误消息，说明文件已被外部修改
  Future<String?> validateSafeToWrite(String filePath) async {
    final normalizedPath = p.normalize(filePath);
    final file = File(normalizedPath);

    // 文件不存在 → 新文件，可以写入
    if (!await file.exists()) return null;

    // 从未读取过 → 不应该直接修改
    final lastRead = _readSnapshots[normalizedPath];
    if (lastRead == null) {
      // 这个检查由 previouslyReadFiles 机制处理
      // 这里只处理陈旧快照检查
      return null;
    }

    final current = await _snapshotFile(file);
    if (lastRead.canCompareContentWith(current)) {
      if (lastRead.hasSameContentAs(current)) return null;
      return _dirtyWriteMessage(filePath, lastRead, current);
    }

    if (lastRead.size != current.size ||
        _timestampDiffExceedsTolerance(lastRead.modified, current.modified)) {
      return _dirtyWriteMessage(filePath, lastRead, current);
    }

    return null;
  }

  /// 清除指定文件的追踪记录
  void clearFileTracking(String filePath) {
    final normalizedPath = p.normalize(filePath);
    _readSnapshots.remove(normalizedPath);
    _readResultSnapshots.remove(normalizedPath);
  }

  /// 清除所有 Read 结果去重记录，保留 read-before-write 快照。
  ///
  /// 历史压缩后，之前的完整 Read tool_result 可能已经不在 prompt 中，
  /// 因此不能继续返回“refer to earlier Read result”的短提示。
  void clearReadResultTracking() {
    _readResultSnapshots.clear();
  }

  /// 清除所有追踪记录（会话重置时调用）
  void clearAllTracking() {
    _readSnapshots.clear();
    _readResultSnapshots.clear();
  }

  /// 更新文件读取快照（写入后需要更新）
  Future<void> updateAfterWrite(String filePath) async {
    // 写入后重新记录快照，因为我们自己的写入是可信的；如果本次 mutation
    // 删除了文件，则清除旧快照，避免后续工具复用已不存在文件的读取状态。
    if (!await File(p.normalize(filePath)).exists()) {
      clearFileTracking(filePath);
      return;
    }
    await recordFileRead(filePath);
  }

  Future<_TrackedFileSnapshot> _snapshotFile(File file) async {
    final stat = await file.stat();
    final digest = await _fingerprintFile(file, stat.size);
    return _TrackedFileSnapshot(
      modified: stat.modified,
      size: stat.size,
      sha256Digest: digest,
    );
  }

  Future<String?> _fingerprintFile(File file, int byteSize) async {
    if (byteSize > _maxFingerprintBytes) return null;
    try {
      return (await sha256.bind(file.openRead()).first).toString();
    } on FileSystemException {
      return null;
    }
  }

  bool _timestampDiffExceedsTolerance(DateTime a, DateTime b) {
    final diff = a.difference(b).abs();
    return diff > _timestampTolerance;
  }

  String _dirtyWriteMessage(
    String filePath,
    _TrackedFileSnapshot lastRead,
    _TrackedFileSnapshot current,
  ) {
    final timeDiff = current.modified.difference(lastRead.modified).abs();
    return 'File was modified externally after last read (${_formatDuration(timeDiff)} difference). '
        'Re-read the file before editing to avoid overwriting external changes: $filePath';
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) return '${duration.inDays}d';
    if (duration.inHours > 0) return '${duration.inHours}h';
    if (duration.inMinutes > 0) return '${duration.inMinutes}m';
    return '${duration.inSeconds}s';
  }
}

class _TrackedFileSnapshot {
  const _TrackedFileSnapshot({
    required this.modified,
    required this.size,
    required this.sha256Digest,
  });

  final DateTime modified;
  final int size;
  final String? sha256Digest;

  bool canCompareContentWith(_TrackedFileSnapshot other) {
    return sha256Digest != null && other.sha256Digest != null;
  }

  bool hasSameContentAs(_TrackedFileSnapshot other) {
    return canCompareContentWith(other) && sha256Digest == other.sha256Digest;
  }
}

class _TrackedReadResult {
  const _TrackedReadResult({
    required this.offset,
    required this.limit,
    required this.snapshot,
  });

  final int offset;
  final int limit;
  final _TrackedFileSnapshot snapshot;
}
